#!/bin/bash
#
# build_bot database 에서 모델/버전에 해당하는 official firmware 를 가져와
# SKB bitbucket 에 버전명 브랜치를 만들어 올리는 스크립트
#
# 사용법:
#   ./release_skb_official_firmware.sh <모델명> <버전> [옵션]
#
# 예시:
#   ./release_skb_official_firmware.sh BFX-UA300 19.561.114
#   ./release_skb_official_firmware.sh BFX-UA300 19.561.114 --dry-run
#   ./release_skb_official_firmware.sh BFX-UA300 --list
#
# 릴리즈 절차 (BFX-UA300 기준으로 확인. 다른 모델도 같은 절차로 동작하며,
#              확인되지 않은 모델은 계획 출력에 표시된다):
#   [release 저장소]  (예: ssh://git@bitbucket.skbroadband.com:7999/stbfw/bfx-ua300_5.6.1.git)
#     1. master clone
#     2. git checkout -b <버전>
#     3. repo_diffmanifests_*.txt 다운로드
#     4. git commit -m "<버전> repo_diffmanifests"
#     5. SU/usb_..._SU.zip 다운로드
#     6. git commit -m "<버전> user firmware"
#     7. 다음 버전(<버전>+1) user firmware 가 있으면 다운로드
#     8. EDMP/ 폴더에 두고 git commit -m "<버전+1> user firmware"
#   [debug 저장소]    (예: ssh://git@bitbucket.skbroadband.com:7999/stbfwdbg/bfx-ua300_5.6.1.git)
#     9. master clone
#    10. git checkout -b <버전>
#    11. SD/usb_..._SD.zip 을 DEBUG/ (BFX-AT400) 또는 DEBUG/sd/ (그 외) 에 두고
#        git commit -m "<버전> userdebug firmware"
#   마지막에 두 저장소 모두 push (확인 프롬프트 있음)
#
#   <버전>+1 빌드가 나중에 완료된 경우:
#     ./release_skb_official_firmware.sh BFX-UA300 <버전> --next-only
#     -> 이미 올라간 <버전> 브랜치를 clone 해서 EDMP/ 에 +1 user firmware 만 추가 커밋
#
#   저장소 주소는 버전(플랫폼 버전)에 따라 달라지므로 처음 실행할 때 한 번만 입력받고,
#   ~/.config/release_skb_official_firmware.repos 에 기억해 두었다가 다음부터는 그대로 쓴다.
#   (다시 입력받으려면 --ask-repo)
#
# 옵션:
#   -n, --dry-run           DB 조회 + 다운로드 + 계획 출력까지만 (git 작업 없음)
#   -y, --yes               프롬프트 없이 진행 (저장된/기본 저장소 주소 사용)
#       --no-push           commit 까지만 하고 push 하지 않음
#       --no-next           다음 버전(+1) user firmware 단계를 건너뜀
#       --next-only         이미 올라간 <버전> 브랜치에 다음 버전(+1) user firmware 만
#                           EDMP/ 로 추가 커밋한다. (+1 빌드가 나중에 완료된 경우)
#                           release 저장소만 건드리고, 그 파일 하나만 받는다.
#       --no-branch-check   원격에 같은 브랜치가 있는지 확인하지 않음 (로컬 브랜치만 생성)
#                           테스트용. push 하면 원격에 있는 경우 거부된다.
#       --ask-repo            기억해 둔 저장소 주소를 무시하고 다시 입력받음
#       --release-repo <url>  release 저장소 주소 지정 (프롬프트 대신)
#       --debug-repo <url>    debug 저장소 주소 지정 (프롬프트 대신)
#       --base-branch <name>  clone 기준 브랜치 (기본: master)
#   -b, --branch <name>     생성할 브랜치명 (기본: 버전명)
#       --any-status        build_status 가 complete 가 아니어도 진행
#       --force             브랜치가 이미 있으면 그 위에 커밋
#       --list              해당 모델의 official 빌드 목록 출력 후 종료
#   -h, --help              도움말
#
set -uo pipefail

CONFIG_FILE="${RELEASE_SKB_CONFIG:-$HOME/.config/release_skb_official_firmware.conf}"
REPO_CACHE="${RELEASE_SKB_REPO_CACHE:-$HOME/.config/release_skb_official_firmware.repos}"
# shellcheck disable=SC1090
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

# --- build_bot 서버 / database --------------------------------------------------
# MySQL 이 localhost 바인딩이라 SSH 로 들어가서 조회한다. (~/.ssh/config 의 Host 이름)
BUILD_BOT_SSH_HOST="${BUILD_BOT_SSH_HOST:-dev2-server03}"
BUILD_BOT_DB_HOST="${BUILD_BOT_DB_HOST:-localhost}"
BUILD_BOT_DB_NAME="${BUILD_BOT_DB_NAME:-build_bot}"
BUILD_BOT_DB_USER="${BUILD_BOT_DB_USER:-build_bot}"
BUILD_BOT_DB_PASS="${BUILD_BOT_DB_PASS:-build_bot11qq}"
SSH_TIMEOUT="${SSH_TIMEOUT:-15}"

# --- 펌웨어 다운로드 (altserver01) ----------------------------------------------
FTP_USER="${FTP_USER:-alt}"
FTP_PASSWORD="${FTP_PASSWORD:-alt1234}"

# --- SKB bitbucket --------------------------------------------------------------
# SKB_DEBUG_SUBDIR 은 모델마다 달라서 모델을 확인한 뒤에 정한다 (아래 참고)
SKB_EDMP_SUBDIR="${SKB_EDMP_SUBDIR:-EDMP}"
BASE_BRANCH="${SKB_BASE_BRANCH:-master}"
SKB_GIT_USER_NAME="${SKB_GIT_USER_NAME:-}"
SKB_GIT_USER_EMAIL="${SKB_GIT_USER_EMAIL:-}"

# ------------------------------------------------------------------------------

SCRIPT_NAME="$(basename "$0")"

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d' >&2; exit "${1:-1}"; }
die()   { echo "에러: $*" >&2; exit 1; }
info()  { echo "==> $*"; }
warn()  { echo "경고: $*" >&2; }

MODEL=""; VERSION=""; BRANCH=""
RELEASE_REPO=""; DEBUG_REPO=""
DRY_RUN=0; ASSUME_YES=0; NO_PUSH=0; NO_NEXT=0; FORCE=0; LIST_ONLY=0; ANY_STATUS=0; ASK_REPO=0; NO_BRANCH_CHECK=0; NEXT_ONLY=0

while [ $# -gt 0 ]; do
    case "$1" in
        -n|--dry-run)     DRY_RUN=1; shift ;;
        -y|--yes)         ASSUME_YES=1; shift ;;
        --no-push)        NO_PUSH=1; shift ;;
        --no-next)        NO_NEXT=1; shift ;;
        --next-only)      NEXT_ONLY=1; shift ;;
        --no-branch-check) NO_BRANCH_CHECK=1; shift ;;
        --ask-repo)       ASK_REPO=1; shift ;;
        --release-repo)   RELEASE_REPO="${2:-}"; shift 2 ;;
        --debug-repo)     DEBUG_REPO="${2:-}"; shift 2 ;;
        --base-branch)    BASE_BRANCH="${2:-}"; shift 2 ;;
        -b|--branch)      BRANCH="${2:-}"; shift 2 ;;
        --any-status)     ANY_STATUS=1; shift ;;
        --force)          FORCE=1; shift ;;
        --list)           LIST_ONLY=1; shift ;;
        -h|--help)        usage 0 ;;
        -*)               die "알 수 없는 옵션: $1" ;;
        *)
            if   [ -z "$MODEL" ];   then MODEL="$1"
            elif [ -z "$VERSION" ]; then VERSION="$1"
            else die "인자가 너무 많습니다: $1"; fi
            shift ;;
    esac
done

[ -n "$MODEL" ] || usage
[ "$LIST_ONLY" -eq 1 ] || [ -n "$VERSION" ] || usage

MODEL="$(echo "$MODEL" | tr '[:lower:]' '[:upper:]')"
VERSION="${VERSION#[Vv]}"

echo "$MODEL" | grep -qE '^[A-Za-z0-9._-]+$' || die "모델명에 허용되지 않는 문자가 있습니다: ${MODEL}"
[ -z "$VERSION" ] || echo "$VERSION" | grep -qE '^[A-Za-z0-9._-]+$' \
    || die "버전에 허용되지 않는 문자가 있습니다: ${VERSION}"

if [ "$NEXT_ONLY" -eq 1 ] && [ "$NO_NEXT" -eq 1 ]; then
    die "--next-only 와 --no-next 는 같이 쓸 수 없습니다."
fi

for bin in curl git ssh; do
    command -v "$bin" >/dev/null 2>&1 || die "'${bin}' 명령을 찾을 수 없습니다."
done

# --- build_bot database --------------------------------------------------------

# SQL 은 stdin 으로 넘긴다 (백틱 이스케이프 문제 회피). 결과는 '|' 구분, 헤더 없음.
db_query() {
    printf '%s\n' "$1" | ssh -o BatchMode=yes -o ConnectTimeout="$SSH_TIMEOUT" \
        "$BUILD_BOT_SSH_HOST" \
        "MYSQL_PWD='${BUILD_BOT_DB_PASS}' mysql -u '${BUILD_BOT_DB_USER}' -h '${BUILD_BOT_DB_HOST}' '${BUILD_BOT_DB_NAME}' -sN" 2>/dev/null
}

if [ "$LIST_ONLY" -eq 1 ]; then
    info "build_bot DB 조회: ${MODEL} official firmware 목록"
    ROWS="$(db_query "
        SELECT CONCAT_WS('|', IFNULL(firmware_version,''), IFNULL(\`fk-os_version\`,''),
               IFNULL(\`fk-build_status\`,''), IFNULL(google_certificated,''),
               IFNULL(tag_name,''), IFNULL(DATE(requested_time),''))
        FROM build_request
        WHERE \`fk-model_name\`='${MODEL}'
          AND \`fk-firmware_type\`='official_firmware'
        ORDER BY build_request_id DESC LIMIT 40;")"
    [ -n "$ROWS" ] || die "DB 에서 결과를 가져오지 못했습니다. (모델명 또는 SSH 접속 확인: ${BUILD_BOT_SSH_HOST})"
    printf "\n%-14s %-4s %-10s %-8s %-12s %s\n" "VERSION" "OS" "STATUS" "GOOGLE" "REQUESTED" "TAG"
    while IFS='|' read -r fw os st gc tag dt; do
        [ -n "$fw" ] || continue
        [ "$gc" = "1" ] && gc="Y" || gc="-"
        printf "%-14s %-4s %-10s %-8s %-12s %s\n" "$fw" "$os" "$st" "$gc" "$dt" "$tag"
    done <<< "$ROWS"
    exit 0
fi

# 릴리즈 절차를 실제로 확인한 모델. 그 외 모델도 같은 절차로 진행하되,
# 계획 출력에서 "확인 필요" 를 한 줄 띄운다.
CONFIRMED_MODELS="${CONFIRMED_MODELS:-BFX-UA300 BFX-AT400}"
MODEL_CONFIRMED=0
for m in $CONFIRMED_MODELS; do
    [ "$m" = "$MODEL" ] && MODEL_CONFIRMED=1
done

# debug 저장소에서 userdebug firmware 를 두는 경로 (모델마다 다르다)
#   BFX-AT400 -> DEBUG
#   그 외      -> DEBUG/sd
# 설정파일/환경변수로 덮어쓰려면 SKB_DEBUG_SUBDIR 또는
# 모델별로 SKB_DEBUG_SUBDIR_BFX_AT400 처럼 지정한다.
case "$MODEL" in
    BFX-AT400) DEBUG_SUBDIR_DEFAULT="DEBUG" ;;
    *)         DEBUG_SUBDIR_DEFAULT="DEBUG/sd" ;;
esac
DEBUG_SUBDIR_VAR="SKB_DEBUG_SUBDIR_$(echo "$MODEL" | tr '-' '_')"
SKB_DEBUG_SUBDIR="${SKB_DEBUG_SUBDIR:-${!DEBUG_SUBDIR_VAR:-$DEBUG_SUBDIR_DEFAULT}}"

# 한 행 조회: build_request_id|os_version|tag_name|build_status|google_certificated|sd_ftp|su_ftp
db_build_row() {
    local version="$1" status_cond=""
    [ "$ANY_STATUS" -eq 1 ] || status_cond="AND \`fk-build_status\`='complete'"
    db_query "
        SELECT CONCAT_WS('|', build_request_id, IFNULL(\`fk-os_version\`,''), IFNULL(tag_name,''),
               IFNULL(\`fk-build_status\`,''), IFNULL(google_certificated,''),
               IFNULL(sd_ftp,''), IFNULL(su_ftp,''))
        FROM build_request
        WHERE \`fk-model_name\`='${MODEL}'
          AND firmware_version='${version}'
          AND \`fk-firmware_type\`='official_firmware'
          ${status_cond}
        ORDER BY build_request_id DESC LIMIT 1;" | head -n 1
}

info "build_bot DB 조회: ${MODEL} ${VERSION} (official_firmware)"
ROW="$(db_build_row "$VERSION")"

if [ -z "$ROW" ]; then
    ALT="$(db_query "
        SELECT CONCAT_WS(' / ', \`fk-firmware_type\`, \`fk-build_status\`)
        FROM build_request
        WHERE \`fk-model_name\`='${MODEL}' AND firmware_version='${VERSION}'
        ORDER BY build_request_id DESC LIMIT 1;" | head -n 1)"
    [ -n "$ALT" ] && die "조건에 맞는 빌드가 없습니다: ${MODEL} ${VERSION}
      DB 에는 있지만 firmware_type/build_status 가 다릅니다 -> ${ALT}
      (상태와 무관하게 진행하려면 --any-status)"
    die "DB 에서 빌드를 찾을 수 없습니다: ${MODEL} ${VERSION}
      ('${SCRIPT_NAME} ${MODEL} --list' 로 목록을 확인하세요)"
fi

IFS='|' read -r REQ_ID OS_VERSION TAG_NAME BUILD_STATUS GOOGLE_CERT SD_FTP SU_FTP <<< "$ROW"

[ -n "$SU_FTP" ] || die "SU 펌웨어 링크가 DB 에 없습니다. (build_request_id=${REQ_ID}, status=${BUILD_STATUS})"
[ -n "$SD_FTP" ] || die "SD 펌웨어 링크가 DB 에 없습니다. (build_request_id=${REQ_ID}, status=${BUILD_STATUS})"

BUILD_URL="${SU_FTP%/SU}"          # 빌드 디렉터리 (SU 상위)
info "빌드 확인: id=${REQ_ID} OS${OS_VERSION} ${TAG_NAME} (${BUILD_STATUS})"

# tag_name(BFX-UA300_5.6.1_2026-0820-173504.xml)에서 플랫폼 버전(5.6.1)을 뽑는다
PLATFORM_VER="$(echo "$TAG_NAME" | cut -d'_' -f2)"
echo "$PLATFORM_VER" | grep -qE '^[0-9]+(\.[0-9]+)*$' \
    || die "tag_name 에서 플랫폼 버전을 인식하지 못했습니다: ${TAG_NAME}"

MODEL_LOWER="$(echo "$MODEL" | tr '[:upper:]' '[:lower:]')"
REPO_KEY="${MODEL}|${PLATFORM_VER}"

# --- 저장소 주소 정하기 ---------------------------------------------------------

cache_get() {  # cache_get <index 3|4>
    [ -f "$REPO_CACHE" ] || return 0
    grep -F "${REPO_KEY}|" "$REPO_CACHE" 2>/dev/null | tail -n 1 | cut -d'|' -f"$1"
}

cache_put() {  # cache_put <release_url> <debug_url>
    mkdir -p "$(dirname "$REPO_CACHE")"
    local tmp; tmp="$(mktemp)"
    [ -f "$REPO_CACHE" ] && grep -vF "${REPO_KEY}|" "$REPO_CACHE" > "$tmp" 2>/dev/null
    printf '%s|%s|%s\n' "$REPO_KEY" "$1" "$2" >> "$tmp"
    mv "$tmp" "$REPO_CACHE"
}

# 저장소 주소는 추측하지 않는다. 처음 한 번은 반드시 직접 입력받고,
# 그 뒤로는 캐시에서 읽어 쓴다. (결과는 ASK_REPO_RESULT 에 담긴다)
ask_repo() {  # ask_repo <라벨> <제안값(없으면 "")>
    local label="$1" suggest="$2" answer=""
    ASK_REPO_RESULT=""

    if [ "$ASSUME_YES" -eq 1 ]; then
        [ -n "$suggest" ] || die "${label} 저장소 주소를 알 수 없습니다.
      -y 로는 물어볼 수 없으니 --release-repo / --debug-repo 로 지정하거나
      -y 없이 한 번 실행해서 입력해 주세요."
        ASK_REPO_RESULT="$suggest"; return
    fi

    while : ; do
        if [ -n "$suggest" ]; then
            read -rp "${label} 저장소 주소 [${suggest}]: " answer < /dev/tty \
                || die "저장소 주소를 입력받지 못했습니다. (--release-repo / --debug-repo 로 지정하세요)"
            answer="${answer:-$suggest}"
        else
            read -rp "${label} 저장소 주소: " answer < /dev/tty \
                || die "저장소 주소를 입력받지 못했습니다. (--release-repo / --debug-repo 로 지정하세요)"
        fi
        [ -n "$answer" ] && break
        echo "  저장소 주소를 입력해 주세요. (취소하려면 Ctrl-C)" >&2
    done
    ASK_REPO_RESULT="$answer"
}

SAVED_RELEASE="$(cache_get 3)"
SAVED_DEBUG="$(cache_get 4)"

# 한 번 입력해 둔 저장소는 다시 묻지 않는다. (다시 입력받으려면 --ask-repo)
if [ "$ASK_REPO" -eq 0 ]; then
    [ -n "$RELEASE_REPO" ] || RELEASE_REPO="$SAVED_RELEASE"
    [ -n "$DEBUG_REPO" ]   || DEBUG_REPO="$SAVED_DEBUG"
fi

# --next-only 는 release 저장소만 쓰므로 debug 는 묻지 않는다
NEED_DEBUG_REPO=1
[ "$NEXT_ONLY" -eq 1 ] && NEED_DEBUG_REPO=0

NEED_ASK=0
[ -z "$RELEASE_REPO" ] && NEED_ASK=1
[ "$NEED_DEBUG_REPO" -eq 1 ] && [ -z "$DEBUG_REPO" ] && NEED_ASK=1

if [ "$NEED_ASK" -eq 1 ]; then
    if [ "$ASSUME_YES" -ne 1 ]; then
        echo ""
        echo "  ${MODEL} (플랫폼 ${PLATFORM_VER}) 저장소 주소를 입력해 주세요."
        echo "  한 번 입력하면 ${REPO_CACHE} 에 저장되어 다음부터는 묻지 않습니다."
    fi
    if [ -z "$RELEASE_REPO" ]; then
        ask_repo "release  (user firmware)" "$SAVED_RELEASE"; RELEASE_REPO="$ASK_REPO_RESULT"
    fi
    if [ "$NEED_DEBUG_REPO" -eq 1 ] && [ -z "$DEBUG_REPO" ]; then
        ask_repo "debug    (userdebug)     " "$SAVED_DEBUG"; DEBUG_REPO="$ASK_REPO_RESULT"
    fi
fi

[ -n "$RELEASE_REPO" ] || die "release 저장소 주소가 필요합니다."
[ "$NEED_DEBUG_REPO" -eq 0 ] || [ -n "$DEBUG_REPO" ] || die "debug 저장소 주소가 필요합니다."

# 캐시에는 사용자가 계획을 확인한 뒤에 기록한다 (아래 remember_repos 참고)
remember_repos() {
    # --next-only 로 debug 를 안 물어봤으면 캐시에 있던 값을 그대로 둔다
    if [ "$RELEASE_REPO" != "$SAVED_RELEASE" ] || \
       { [ -n "$DEBUG_REPO" ] && [ "$DEBUG_REPO" != "$SAVED_DEBUG" ]; }; then
        cache_put "$RELEASE_REPO" "${DEBUG_REPO:-$SAVED_DEBUG}"
        info "저장소 주소를 기억했습니다: ${REPO_CACHE}"
    fi
}

[ -n "$BRANCH" ] || BRANCH="$VERSION"

# --- 다운로드 대상 정하기 -------------------------------------------------------

list_dir() {
    curl -fsS -m 60 --user "${FTP_USER}:${FTP_PASSWORD}" "$1" 2>/dev/null \
        | grep -oE 'href="[^"]+"' | sed -e 's/^href="//' -e 's/"$//' \
        | grep -v '^?' | grep -v '^/'
}

url_exists() {
    curl -fsIL -m 30 --user "${FTP_USER}:${FTP_PASSWORD}" -o /dev/null "$1"
}

human_size() {
    awk -v b="$1" 'BEGIN{ if (b>=1048576) printf "%.1f MiB", b/1048576; else printf "%.1f KiB", b/1024 }'
}

# 3. repo_diffmanifests_*.txt (이전 버전이 -1 이 아닐 수 있어 디렉터리에서 찾는다)
DIFF_NAME=""; SU_NAME=""; SD_NAME=""
if [ "$NEXT_ONLY" -eq 0 ]; then
    DIFF_NAME="$(list_dir "${BUILD_URL}/" | grep -E '^repo_diffmanifests_.*\.txt$' | tail -n 1)"
    [ -n "$DIFF_NAME" ] || die "repo_diffmanifests 파일을 찾을 수 없습니다: ${BUILD_URL}/"

    SU_NAME="usb_${MODEL_LOWER}_V${VERSION}_SU.zip"
    SD_NAME="usb_${MODEL_LOWER}_V${VERSION}_SD.zip"
    url_exists "${SU_FTP}/${SU_NAME}" || die "user firmware 를 찾을 수 없습니다: ${SU_FTP}/${SU_NAME}"
    url_exists "${SD_FTP}/${SD_NAME}" || die "userdebug firmware 를 찾을 수 없습니다: ${SD_FTP}/${SD_NAME}"
fi

# 7. 다음 버전(마지막 자리 +1) user firmware
NEXT_VERSION=""; NEXT_SU_URL=""; NEXT_SU_NAME=""
if [ "$NO_NEXT" -eq 0 ]; then
    NEXT_VERSION="${VERSION%.*}.$(( ${VERSION##*.} + 1 ))"
    NEXT_ROW="$(db_build_row "$NEXT_VERSION")"
    if [ -n "$NEXT_ROW" ]; then
        IFS='|' read -r _ _ _ _ _ _ NEXT_SU_FTP <<< "$NEXT_ROW"
        NEXT_SU_NAME="usb_${MODEL_LOWER}_V${NEXT_VERSION}_SU.zip"
        if [ -n "$NEXT_SU_FTP" ] && url_exists "${NEXT_SU_FTP}/${NEXT_SU_NAME}"; then
            NEXT_SU_URL="${NEXT_SU_FTP}/${NEXT_SU_NAME}"
        else
            [ "$NEXT_ONLY" -eq 1 ] && die "다음 버전 user firmware 가 아직 없습니다: ${NEXT_SU_FTP}/${NEXT_SU_NAME}"
            info "다음 버전 ${NEXT_VERSION} user firmware 없음 - 건너뜁니다."
            NEXT_VERSION=""
        fi
    else
        [ "$NEXT_ONLY" -eq 1 ] && die "다음 버전 빌드가 아직 DB 에 없습니다: ${MODEL} ${NEXT_VERSION}
      ('${SCRIPT_NAME} ${MODEL} --list' 로 확인하세요. 상태가 complete 가 아니면 --any-status)"
        info "다음 버전 ${NEXT_VERSION} 빌드 없음 - 건너뜁니다."
        NEXT_VERSION=""
    fi
fi

# --- 브랜치 중복 확인 (다운로드 전에) -------------------------------------------

remote_branch_exists() {
    git ls-remote --exit-code --heads "$1" "$BRANCH" >/dev/null 2>&1
}

check_branch() {  # check_branch <라벨> <url> -> 0: 없음, 1: 있음
    if remote_branch_exists "$2"; then
        [ "$FORCE" -eq 1 ] || die "$1 저장소에 브랜치가 이미 있습니다: ${BRANCH}
      $2
      (그 위에 커밋하려면 --force)"
        return 1
    fi
    return 0
}

RELEASE_BRANCH_EXISTS=0
DEBUG_BRANCH_EXISTS=0
if [ "$NEXT_ONLY" -eq 1 ]; then
    if [ "$NO_BRANCH_CHECK" -eq 1 ]; then
        # 테스트용: 원격에 브랜치가 있으면 그걸, 없으면 master 에서 새로 만든다
        remote_branch_exists "$RELEASE_REPO" && RELEASE_BRANCH_EXISTS=1
        warn "원격 브랜치 확인을 건너뜁니다 (--no-branch-check)."
    else
        info "브랜치 확인: ${BRANCH}"
        remote_branch_exists "$RELEASE_REPO" || die "release 저장소에 브랜치가 없습니다: ${BRANCH}
      ${RELEASE_REPO}
      --next-only 은 이미 올라간 브랜치에 +1 펌웨어만 추가하는 모드입니다.
      브랜치부터 만들려면 --next-only 없이 실행하세요."
        RELEASE_BRANCH_EXISTS=1
    fi
elif [ "$NO_BRANCH_CHECK" -eq 1 ]; then
    warn "원격 브랜치 중복 확인을 건너뜁니다 (--no-branch-check).
      master 를 clone 해서 로컬에만 ${BRANCH} 브랜치를 만듭니다.
      원격에 같은 브랜치가 있으면 push 단계에서 거부됩니다."
elif [ "$DRY_RUN" -eq 0 ]; then
    info "브랜치 중복 확인: ${BRANCH}"
    check_branch "release" "$RELEASE_REPO" || RELEASE_BRANCH_EXISTS=1
    check_branch "debug"   "$DEBUG_REPO"   || DEBUG_BRANCH_EXISTS=1
fi

# --- 계획 출력 ------------------------------------------------------------------

echo ""
echo "  모델 / 버전   : ${MODEL} ${VERSION}"
echo "  빌드          : id=${REQ_ID}  OS${OS_VERSION}  ${TAG_NAME}"
echo "  브랜치        : ${BRANCH}  (기준: ${BASE_BRANCH})"
echo ""
echo "  [release] ${RELEASE_REPO}"
if [ "$NEXT_ONLY" -eq 0 ]; then
echo "     + ${DIFF_NAME}"
echo "         -> commit \"${VERSION} repo_diffmanifests\""
echo "     + ${SU_NAME}"
echo "         -> commit \"${VERSION} user firmware\""
fi
if [ -n "$NEXT_VERSION" ]; then
echo "     + ${SKB_EDMP_SUBDIR}/${NEXT_SU_NAME}"
echo "         -> commit \"${NEXT_VERSION} user firmware\""
fi
if [ "$NEXT_ONLY" -eq 0 ]; then
echo ""
echo "  [debug]   ${DEBUG_REPO}"
echo "     + ${SKB_DEBUG_SUBDIR}/${SD_NAME}"
echo "         -> commit \"${VERSION} userdebug firmware\""
fi
echo ""
if [ "$MODEL_CONFIRMED" -eq 0 ]; then
    echo "  ※ ${MODEL} 의 릴리즈 절차는 BFX-UA300 과 동일하다고 가정했습니다."
    echo "    저장소 주소와 파일 배치가 맞는지 위 계획을 확인하고 진행하세요."
    echo ""
fi
if [ "$NO_PUSH" -eq 1 ]; then
    echo "  push: 안 함 (--no-push)"
elif [ "$NEXT_ONLY" -eq 1 ]; then
    echo "  push: release 저장소 origin ${BRANCH}"
else
    echo "  push: 두 저장소 모두 origin ${BRANCH}"
fi
echo ""

if [ "$ASSUME_YES" -ne 1 ]; then
    read -rp "진행할까요? [y/N] " answer < /dev/tty
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "취소했습니다."; exit 0 ;;
    esac
fi

remember_repos

# --- 다운로드 -------------------------------------------------------------------

WORK_DIR="$(mktemp -d /tmp/release_skb_fw.XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT
DL_DIR="${WORK_DIR}/download"; mkdir -p "$DL_DIR"

fetch() {  # fetch <url> <dest>
    info "다운로드: $(basename "$2")"
    curl -fL --progress-bar -m 3600 --user "${FTP_USER}:${FTP_PASSWORD}" "$1" -o "$2" \
        || die "다운로드에 실패했습니다: $1"
    [ -s "$2" ] || die "다운로드한 파일이 비어 있습니다: $1"
    info "완료: $(human_size "$(wc -c < "$2" | tr -d ' ')")"
}

if [ "$NEXT_ONLY" -eq 0 ]; then
    fetch "${BUILD_URL}/${DIFF_NAME}"  "${DL_DIR}/${DIFF_NAME}"
    fetch "${SU_FTP}/${SU_NAME}"       "${DL_DIR}/${SU_NAME}"
    fetch "${SD_FTP}/${SD_NAME}"       "${DL_DIR}/${SD_NAME}"
fi
[ -n "$NEXT_VERSION" ] && fetch "$NEXT_SU_URL" "${DL_DIR}/${NEXT_SU_NAME}"

if [ "$DRY_RUN" -eq 1 ]; then
    KEEP="${PWD}/${MODEL}_${VERSION}"
    mkdir -p "$KEEP" && cp "$DL_DIR"/* "$KEEP"/ \
        && info "dry-run: 다운로드만 하고 종료합니다 -> ${KEEP}"
    exit 0
fi

# --- git 작업 -------------------------------------------------------------------

prepare_repo() {  # prepare_repo <url> <local_dir> <branch_exists>
    local url="$1" dir="$2" exists="$3" clone_branch="$BASE_BRANCH"

    if [ "$exists" -eq 1 ]; then
        clone_branch="$BRANCH"
        info "기존 브랜치를 이어서 커밋합니다: ${BRANCH}"
    fi

    info "clone: ${url} (${clone_branch})"
    git clone --depth 1 --single-branch --branch "$clone_branch" "$url" "$dir" \
        || die "clone 에 실패했습니다: ${url} (${clone_branch})"

    [ -n "$SKB_GIT_USER_NAME" ]  && git -C "$dir" config user.name  "$SKB_GIT_USER_NAME"
    [ -n "$SKB_GIT_USER_EMAIL" ] && git -C "$dir" config user.email "$SKB_GIT_USER_EMAIL"

    if [ "$exists" -eq 0 ]; then
        info "브랜치 생성: git checkout -b ${BRANCH}"
        git -C "$dir" checkout -b "$BRANCH" || die "브랜치 생성에 실패했습니다: ${BRANCH}"
    fi
}

add_and_commit() {  # add_and_commit <repo_dir> <src_file> <dest_rel_path> <message>
    local dir="$1" src="$2" dest="$3" msg="$4"

    [ "$(dirname "$dest")" != "." ] && mkdir -p "${dir}/$(dirname "$dest")"
    cp "$src" "${dir}/${dest}" || die "파일 복사에 실패했습니다: ${dest}"
    git -C "$dir" add -- "$dest" || die "git add 에 실패했습니다: ${dest}"

    if git -C "$dir" diff --cached --quiet; then
        warn "변경 없음 - 커밋을 건너뜁니다: ${dest}"
        return 0
    fi
    info "commit: \"${msg}\"  (${dest})"
    git -C "$dir" commit -q -m "$msg" || die "커밋에 실패했습니다: ${msg}"
}

RELEASE_DIR="${WORK_DIR}/release"
DEBUG_DIR="${WORK_DIR}/debug"

# [release 저장소] 1~8
echo ""; info "=== release 저장소 작업 ==="
prepare_repo "$RELEASE_REPO" "$RELEASE_DIR" "$RELEASE_BRANCH_EXISTS"
if [ "$NEXT_ONLY" -eq 0 ]; then
    add_and_commit "$RELEASE_DIR" "${DL_DIR}/${DIFF_NAME}" "$DIFF_NAME" "${VERSION} repo_diffmanifests"
    add_and_commit "$RELEASE_DIR" "${DL_DIR}/${SU_NAME}"   "$SU_NAME"   "${VERSION} user firmware"
fi
if [ -n "$NEXT_VERSION" ]; then
    add_and_commit "$RELEASE_DIR" "${DL_DIR}/${NEXT_SU_NAME}" "${SKB_EDMP_SUBDIR}/${NEXT_SU_NAME}" "${NEXT_VERSION} user firmware"
fi

# [debug 저장소] 9~11
if [ "$NEXT_ONLY" -eq 0 ]; then
    echo ""; info "=== debug 저장소 작업 ==="
    prepare_repo "$DEBUG_REPO" "$DEBUG_DIR" "$DEBUG_BRANCH_EXISTS"
    add_and_commit "$DEBUG_DIR" "${DL_DIR}/${SD_NAME}" "${SKB_DEBUG_SUBDIR}/${SD_NAME}" "${VERSION} userdebug firmware"
fi

if [ "$NO_PUSH" -eq 1 ]; then
    KEEP_DIR="${PWD}/${MODEL}_${VERSION}_repos"
    rm -rf "$KEEP_DIR"; mkdir -p "$KEEP_DIR"
    cp -R "$RELEASE_DIR" "${KEEP_DIR}/release" || die "작업 디렉터리를 옮기지 못했습니다: ${KEEP_DIR}"
    echo ""
    info "--no-push: commit 까지만 했습니다. 아래에서 확인 후 직접 push 하세요."
    echo "  git -C ${KEEP_DIR}/release push -u origin ${BRANCH}"
    if [ "$NEXT_ONLY" -eq 0 ]; then
        cp -R "$DEBUG_DIR" "${KEEP_DIR}/debug" || die "작업 디렉터리를 옮기지 못했습니다: ${KEEP_DIR}"
        echo "  git -C ${KEEP_DIR}/debug   push -u origin ${BRANCH}"
    fi
    exit 0
fi

# --- push -----------------------------------------------------------------------

echo ""
info "=== push ==="
PUSH_FAIL=0
info "push: release -> origin ${BRANCH}"
git -C "$RELEASE_DIR" push -u origin "$BRANCH" || { warn "release 저장소 push 실패"; PUSH_FAIL=1; }
if [ "$NEXT_ONLY" -eq 0 ]; then
    info "push: debug -> origin ${BRANCH}"
    git -C "$DEBUG_DIR" push -u origin "$BRANCH" || { warn "debug 저장소 push 실패"; PUSH_FAIL=1; }
fi

echo ""
if [ "$PUSH_FAIL" -eq 1 ]; then
    die "일부 저장소 push 에 실패했습니다. (권한/브랜치 정책/파일 크기 제한 확인)"
fi
if [ "$NEXT_ONLY" -eq 1 ]; then
    echo "완료: ${NEXT_VERSION} user firmware 를 '${BRANCH}' 브랜치의 ${SKB_EDMP_SUBDIR}/ 에 추가했습니다."
    echo "  release: ${RELEASE_REPO}"
else
    echo "완료: ${MODEL} ${VERSION} 을(를) '${BRANCH}' 브랜치로 업로드했습니다."
    echo "  release: ${RELEASE_REPO}"
    echo "  debug  : ${DEBUG_REPO}"
fi
