#!/bin/bash
#
# 빌드 서버에서 .so 파일을 받아 기기에 push하고 재부팅하는 스크립트
#
# 사용법:
#   ./push_swan_lib_to_device.sh [옵션] <라이브러리파일명>
#
# 예시:
#   ./push_swan_lib_to_device.sh libbtvhal_setting.so
#   ./push_swan_lib_to_device.sh -p BFX-UA300_OS10 -o BFX-UA300 libfoo.so
#   ./push_swan_lib_to_device.sh -r 64 libbar.so   # lib64로 push
#
set -e

# ---- 기본값 (환경변수로도 override 가능) ----
SSH_HOST="${SSH_HOST:-altserver01.iptime.org}"
SSH_PORT="${SSH_PORT:-803}"
SSH_USER="${SSH_USER:-smchoi}"
PROJECT_DIR="${PROJECT_DIR:-BFX-UA300_OS10}"   # ~/project/ 밑의 프로젝트 폴더명
PRODUCT="${PRODUCT:-BFX-UA300}"                 # out/target/product/<PRODUCT>
LIB_ARCH=""                                     # "" -> lib, "64" -> lib64
DO_REBOOT=1

usage() {
    cat <<EOF
사용법: $(basename "$0") [옵션] <so파일명>

옵션:
  -p <project_dir>   원격 프로젝트 디렉토리명 (기본: $PROJECT_DIR)
  -o <product>        out/target/product 아래의 product명 (기본: $PRODUCT)
  -r <32|64>          push할 lib 경로 (lib 또는 lib64, 기본: lib)
  -n                   push 후 reboot 하지 않음
  -h                   도움말 출력
EOF
    exit 1
}

while getopts "p:o:r:nh" opt; do
    case "$opt" in
        p) PROJECT_DIR="$OPTARG" ;;
        o) PRODUCT="$OPTARG" ;;
        r) [ "$OPTARG" = "64" ] && LIB_ARCH="64" ;;
        n) DO_REBOOT=0 ;;
        h) usage ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

if [ $# -lt 1 ]; then
    echo "에러: so 파일명을 입력하세요." >&2
    usage
fi

LIB_NAME="$1"
LIB_DIR="lib${LIB_ARCH}"

REMOTE_PATH="/home/${SSH_USER}/project/${PROJECT_DIR}/out/target/product/${PRODUCT}/symbols/vendor/${LIB_DIR}/${LIB_NAME}"
DEVICE_PATH="/vendor/${LIB_DIR}/${LIB_NAME}"
LOCAL_FILE="./${LIB_NAME}"

echo "==> scp: ${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}"
scp -P "$SSH_PORT" "${SSH_USER}@${SSH_HOST}:${REMOTE_PATH}" "$LOCAL_FILE"

echo "==> adb root"
adb root

echo "==> adb remount"
adb remount

echo "==> adb push: ${LOCAL_FILE} -> ${DEVICE_PATH}"
adb push "$LOCAL_FILE" "$DEVICE_PATH"

if [ "$DO_REBOOT" -eq 1 ]; then
    echo "==> adb shell reboot"
    adb shell reboot
else
    echo "==> reboot 생략(-n 옵션)"
fi
