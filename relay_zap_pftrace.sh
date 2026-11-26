#!/bin/bash
#
# zap_test의 파일(perfetto trace, 로그 등)을 에이징 서버에서 받아 BFX-AT400 빌드 서버로 올리는 스크립트
#
# 동작:
#   1. smchoi@100.76.143.99:/home/aging_bot/project/zap_test/<파일명> 을 현재 폴더로 scp
#   2. 받은 파일을 smchoi@192.168.201.9:/mnt/nvme1n1/smchoi/project/BFX-AT400/claude_works/zap_test/ 로 scp
#
# 사용법:
#   ./relay_zap_pftrace.sh <파일명>
#
# 예시:
#   ./relay_zap_pftrace.sh perfetto_192.168.40.136_20261106_121140.pftrace
#   ./relay_zap_pftrace.sh BFX-AT400_24.562.2503_zap_20261106_132235.log
#
set -uo pipefail

SRC_HOST="smchoi@100.76.143.99"
SRC_DIR="/home/aging_bot/project/zap_test"
DST_HOST="smchoi@192.168.201.9"
DST_DIR="/mnt/nvme1n1/smchoi/project/BFX-AT400/claude_works/zap_test"

usage() {
    echo "사용법: $(basename "$0") <파일명>" >&2
    echo "예:     $(basename "$0") perfetto_192.168.40.136_20261106_121140.pftrace" >&2
    exit 1
}

[ $# -eq 1 ] || usage

# 경로를 붙여 넣어도 파일명만 사용한다.
FILE="$(basename "$1")"

if [[ ! "$FILE" =~ ^[A-Za-z0-9_][A-Za-z0-9._-]*$ ]]; then
    echo "에러: 파일명은 영문/숫자/._- 만 사용할 수 있고 '.'이나 '-'로 시작할 수 없습니다: ${FILE}" >&2
    exit 1
fi

command -v scp >/dev/null 2>&1 || { echo "에러: 'scp' 명령을 찾을 수 없습니다." >&2; exit 1; }

echo "==> 다운로드: ${SRC_HOST}:${SRC_DIR}/${FILE}"
if ! scp "${SRC_HOST}:${SRC_DIR}/${FILE}" "./${FILE}"; then
    echo "에러: 다운로드에 실패했습니다: ${SRC_HOST}:${SRC_DIR}/${FILE}" >&2
    exit 1
fi

echo "==> 업로드: ${FILE} -> ${DST_HOST}:${DST_DIR}/"
if ! scp "./${FILE}" "${DST_HOST}:${DST_DIR}/"; then
    echo "에러: 업로드에 실패했습니다: ${DST_HOST}:${DST_DIR}/" >&2
    exit 1
fi

echo "완료: ${DST_HOST}:${DST_DIR}/${FILE}"
