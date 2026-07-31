#!/bin/bash
#
# smoke test 결과 json 파일을 buildFingerPrint의 모델명을 보고
# 알맞은 서버로 scp 업로드하는 스크립트
#
# 사용법:
#   ./push_smoke_test_json.sh <json_file>
#
set -euo pipefail

usage() {
    echo "사용법: $(basename "$0") <json_file>" >&2
    exit 1
}

[ $# -eq 1 ] || usage
JSON_FILE="$1"

[ -f "$JSON_FILE" ] || { echo "에러: 파일을 찾을 수 없습니다: $JSON_FILE" >&2; exit 1; }

command -v python3 >/dev/null 2>&1 || { echo "에러: python3가 필요합니다." >&2; exit 1; }

BUILD_FINGERPRINT="$(python3 -c 'import json, sys
with open(sys.argv[1]) as f:
    print(json.load(f)["buildFingerPrint"])' "$JSON_FILE" 2>/dev/null)"

if [ -z "$BUILD_FINGERPRINT" ]; then
    echo "에러: buildFingerPrint 값을 읽을 수 없습니다: $JSON_FILE" >&2
    exit 1
fi

# buildFingerPrint 형식: BRAND/PRODUCT/DEVICE:RELEASE/ID/INCREMENTAL:TYPE/TAGS
# 세 번째 필드(DEVICE:RELEASE)에서 ':' 앞부분이 모델명이다. (예: BFX-UA300)
MODEL="$(echo "$BUILD_FINGERPRINT" | cut -d'/' -f3 | cut -d':' -f1)"

if [ -z "$MODEL" ]; then
    echo "에러: buildFingerPrint에서 모델명을 추출하지 못했습니다: ${BUILD_FINGERPRINT}" >&2
    exit 1
fi

case "$MODEL" in
    BFX-AT400) REMOTE="dev2-google11@192.168.3.211:/home/dev2-google11/android-tvts/latest/android-tvts/tools" ;;
    BFX-AT100) REMOTE="dev2-google02@192.168.2.202:/home/dev2-google02/android-tvts/latest/android-tvts/tools" ;;
    BFX-UA300) REMOTE="dev2-google04@192.168.2.204:/home/dev2-google04/android-tvts/latest/android-tvts/tools" ;;
    *)
        echo "에러: 알 수 없는 모델입니다: ${MODEL} (buildFingerPrint: ${BUILD_FINGERPRINT})" >&2
        exit 1
        ;;
esac

echo "==> 모델 확인: ${MODEL}"
echo "==> scp: ${JSON_FILE} -> ${REMOTE}"
scp "$JSON_FILE" "$REMOTE"
