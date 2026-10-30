#!/bin/bash
#
# 로그 파일/폴더를 모델별 빌드 서버의 logs 폴더로 scp 업로드하는 스크립트
#
# 동작:
#   1. 파라미터로 받은 로그 파일 또는 폴더(여러 개 가능)를 확인한다.
#   2. 모델을 화살표(↑/↓) + Enter로 선택한다. (모델별 접속정보는 아래 LOG_MODELS/LOG_HOSTS/LOG_PORTS/LOG_DIRS 참고)
#      - 첫 번째 파라미터 이름에 모델명이 들어있으면 그 모델에 커서가 먼저 가 있다.
#   3. 이슈번호(예: BPM-58172)를 입력받는다.
#      - 입력하면 <logs>/<이슈번호>/ 에, 그냥 Enter면 <logs>/ 에 업로드
#   4. 원격에 폴더가 없으면 mkdir -p로 만든 뒤 scp (폴더는 scp -r)
#
# 사용법:
#   ./upload_log_for_claude.sh <로그 파일 | 로그 폴더> [...]
#
# 예시:
#   ./upload_log_for_claude.sh BFX-AT400_24.562.1901_logcat_20261030_150900.txt
#   ./upload_log_for_claude.sh serial_logs/
#
set -uo pipefail

# 모델별 업로드 서버 정보. (같은 인덱스끼리 대응, bash 3 호환을 위해 배열로 관리)
LOG_MODELS=(BFX-UA300 BFX-AT100 BFX-AT400)
LOG_HOSTS=(smchoi@192.168.201.8 smchoi@192.168.201.8 smchoi@192.168.201.9)
LOG_PORTS=("" "" "")
LOG_DIRS=(/home/smchoi/project/BFX-UA300_OS10/logs /home/smchoi/project/BFX-AT100_OS12/logs /mnt/nvme1n1/smchoi/project/BFX-AT400/logs)

usage() {
    echo "사용법: $(basename "$0") <로그 파일 | 로그 폴더> [...]" >&2
    echo "예:     $(basename "$0") BFX-AT400_24.562.1901_logcat_20261030_150900.txt" >&2
    echo "        $(basename "$0") serial_logs/" >&2
    exit 1
}

[ $# -ge 1 ] || usage

for path in "$@"; do
    if [ ! -e "$path" ]; then
        echo "에러: 파일 또는 폴더를 찾을 수 없습니다: ${path}" >&2
        exit 1
    fi
    if [ ! -r "$path" ]; then
        echo "에러: 읽을 수 없습니다: ${path}" >&2
        exit 1
    fi
done

for bin in ssh scp; do
    command -v "$bin" >/dev/null 2>&1 || { echo "에러: '${bin}' 명령을 찾을 수 없습니다." >&2; exit 1; }
done

# 화살표(↑/↓) + Enter로 고르는 메뉴. (upgrade_firmware.sh와 동일)
# 호출하는 쪽에서 local 배열 `options`를 준비해두면 되고, ARROW_MENU_DEFAULT로 처음 커서 위치를 줄 수 있다.
# 결과는 ARROW_MENU_RESULT(선택된 문자열), ARROW_MENU_INDEX(선택된 인덱스)에 담긴다.
arrow_menu() {
    local count=${#options[@]}
    local sel=${ARROW_MENU_DEFAULT:-0}
    local i key rest

    tput civis 2>/dev/null
    while true; do
        for i in "${!options[@]}"; do
            printf "\033[2K"
            if [ "$i" -eq "$sel" ]; then
                printf "  \033[7m%s\033[0m\n" "${options[$i]}"
            else
                printf "  %s\n" "${options[$i]}"
            fi
        done

        IFS= read -rsn1 key
        if [ "$key" = $'\x1b' ]; then
            IFS= read -rsn2 -t 1 rest
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + count) % count )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % count )) ;;
            "") break ;;
        esac

        tput cuu "$count" 2>/dev/null
    done
    tput cnorm 2>/dev/null

    ARROW_MENU_RESULT="${options[$sel]}"
    ARROW_MENU_INDEX="$sel"
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

# 첫 번째 파라미터 이름에 모델명이 들어있으면 그 모델을 기본 선택으로 둔다.
ARROW_MENU_DEFAULT=0
FIRST_UPPER="$(to_upper "$(basename "$1")")"
for i in "${!LOG_MODELS[@]}"; do
    case "$FIRST_UPPER" in
        *"$(to_upper "${LOG_MODELS[$i]}")"*) ARROW_MENU_DEFAULT="$i"; break ;;
    esac
done

echo "업로드할 모델을 선택하세요: (↑/↓ 이동, Enter 선택)"
options=()
for i in "${!LOG_MODELS[@]}"; do
    options+=("${LOG_MODELS[$i]}  (${LOG_HOSTS[$i]}:${LOG_DIRS[$i]})")
done
options+=("업로드하지 않고 종료")
arrow_menu
IDX="$ARROW_MENU_INDEX"
echo ""

if [ "$IDX" -ge "${#LOG_MODELS[@]}" ]; then
    echo "업로드를 취소합니다."
    exit 0
fi

MODEL="${LOG_MODELS[$IDX]}"
REMOTE_HOST="${LOG_HOSTS[$IDX]}"
REMOTE_PORT="${LOG_PORTS[$IDX]}"
REMOTE_DIR="${LOG_DIRS[$IDX]}"

while true; do
    read -rp "이슈번호를 입력하세요 (예: BPM-58172, 없으면 Enter): " ISSUE
    ISSUE="$(echo "$ISSUE" | tr -d '[:space:]')"
    case "$ISSUE" in
        */*|.|..) echo "이슈번호에 '/'나 '.', '..'은 사용할 수 없습니다." >&2 ;;
        *) break ;;
    esac
done

# 클립보드에 복사할 경로는 프로젝트 폴더 기준 상대경로 (예: logs/BPM-58172/<파일명>)
REL_DIR="$(basename "$REMOTE_DIR")"
if [ -n "$ISSUE" ]; then
    REMOTE_DIR="${REMOTE_DIR}/${ISSUE}"
    REL_DIR="${REL_DIR}/${ISSUE}"
fi

# mkdir과 scp가 한 번의 접속을 공유하도록 해서 비밀번호를 두 번 묻지 않게 한다.
CTRL_DIR="$(mktemp -d /tmp/upload_log_for_claude.XXXXXX)"
cleanup() {
    ssh -o ControlPath="${CTRL_DIR}/ctrl" -O exit "$REMOTE_HOST" >/dev/null 2>&1
    rm -rf "$CTRL_DIR"
}
trap cleanup EXIT

SSH_OPTS=(-o ControlMaster=auto -o ControlPath="${CTRL_DIR}/ctrl" -o ControlPersist=60)
SSH_PORT_OPT=()
SCP_PORT_OPT=()
if [ -n "$REMOTE_PORT" ]; then
    SSH_PORT_OPT=(-p "$REMOTE_PORT")
    SCP_PORT_OPT=(-P "$REMOTE_PORT")
fi

echo "==> 모델: ${MODEL}"
echo "==> 원격 폴더 생성: ${REMOTE_HOST}:${REMOTE_DIR}"
if ! ssh "${SSH_OPTS[@]}" ${SSH_PORT_OPT[@]+"${SSH_PORT_OPT[@]}"} "$REMOTE_HOST" "mkdir -p '${REMOTE_DIR}'"; then
    echo "에러: 원격 폴더를 만들지 못했습니다: ${REMOTE_HOST}:${REMOTE_DIR}" >&2
    exit 1
fi

FAILED=0
UPLOADED=()
for path in "$@"; do
    path="${path%/}"
    echo "==> scp: ${path} -> ${REMOTE_HOST}:${REMOTE_DIR}/"
    SCP_R=()
    [ -d "$path" ] && SCP_R=(-r)
    if scp ${SCP_R[@]+"${SCP_R[@]}"} "${SSH_OPTS[@]}" ${SCP_PORT_OPT[@]+"${SCP_PORT_OPT[@]}"} "$path" "${REMOTE_HOST}:${REMOTE_DIR}/"; then
        UPLOADED+=("${REL_DIR}/$(basename "$path")")
    else
        FAILED=1
    fi
done

# 업로드된 경로를 한 줄에 하나씩 클립보드에 복사한다.
if [ ${#UPLOADED[@]} -gt 0 ]; then
    CLIP_TEXT="$(printf '%s\n' "${UPLOADED[@]}")"
    CLIP_CMD=""
    if command -v pbcopy >/dev/null 2>&1; then
        CLIP_CMD="pbcopy"
    elif command -v wl-copy >/dev/null 2>&1; then
        CLIP_CMD="wl-copy"
    elif command -v xclip >/dev/null 2>&1; then
        CLIP_CMD="xclip -selection clipboard"
    fi

    if [ -n "$CLIP_CMD" ] && printf '%s' "$CLIP_TEXT" | $CLIP_CMD; then
        echo "==> 클립보드에 복사했습니다:"
    else
        echo "경고: 클립보드에 복사하지 못했습니다. 아래 경로를 직접 복사하세요:" >&2
    fi
    echo "$CLIP_TEXT"
fi

if [ "$FAILED" -ne 0 ]; then
    echo "에러: 일부 업로드에 실패했습니다." >&2
    exit 1
fi

echo "완료: ${REMOTE_HOST}:${REMOTE_DIR}/ 에 업로드했습니다."
