#!/usr/bin/env bash
#
# CSV 파일(원본 그대로)을 voc_${시작날짜}_${종료날짜}_${모델명}_${버전}.csv
# 이름으로 바꿔 원격 서버에 scp 업로드한다.
#
# 시작/종료 날짜는 CSV 전체에서 가장 빠른/늦은 날짜를 사용한다.
# (지원 컬럼: MODEL_NAME/@cnsl_timestamp per hour 또는 CUSTOMER_MODEL_NAME/MANUFACTURING_DATE)
# 업로드할 모델/버전 조합은 CSV에서 자동으로 뽑지 않고, 인자로 직접 지정한다.
# 파일 내용은 쪼개지 않고, 조합 수만큼 같은 원본 파일을 이름만 바꿔 반복 업로드한다.
#
# CSV 파싱은 quote/임베디드 콤마·개행이 있는 파일도 안전하게 처리하기 위해
# voc_csv_info.py(csv 모듈)를 사용한다.
#
# 사용법:
#   ./upload_weekly_voc.sh [-n] <csv_file> <모델:버전> [<모델:버전> ...]
#
#   -n   dry-run: scp 없이 결과 파일명만 출력
#
# 예)
#   ./upload_weekly_voc.sh MP_data.csv \
#       BFX-AT400:24.561.130 \
#       BFX-UA300:19.551.30
#   -> voc_2026-07-20_2026-07-22_BFX-AT400_24.561.130.csv
#      voc_2026-07-20_2026-07-22_BFX-UA300_19.551.30.csv
#
# 업로드 대상 모델/버전은 나중에 바뀔 수 있으므로, 스크립트를 고치지 말고
# 매번 인자로 원하는 조합을 넘겨서 사용한다.

set -euo pipefail

REMOTE_USER="aging_bot"
REMOTE_HOST="100.76.143.99"
REMOTE_DIR="/home/aging_bot/project/weekly_voc_analysis"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_INFO_PY="$SCRIPT_DIR/voc_csv_info.py"

DRY_RUN=0

usage() {
    echo "사용법: $0 [-n] <csv_file> <모델:버전> [<모델:버전> ...]" >&2
    echo "예: $0 MP_data.csv BFX-AT400:24.561.130 BFX-UA300:19.551.30" >&2
    exit 1
}

while getopts "n" opt; do
    case "$opt" in
        n) DRY_RUN=1 ;;
        *) usage ;;
    esac
done
shift $((OPTIND - 1))

[ $# -ge 2 ] || usage

CSV_FILE="$1"
shift
PAIR_ARGS=("$@")

[ -f "$CSV_FILE" ] || { echo "파일을 찾을 수 없습니다: $CSV_FILE" >&2; exit 1; }

case "$CSV_FILE" in
    *.csv|*.CSV) ;;
    *) echo "csv 파일이 아닙니다: $CSV_FILE" >&2; exit 1 ;;
esac

for pair in "${PAIR_ARGS[@]}"; do
    case "$pair" in
        *:*) ;;
        *) echo "모델:버전 형식이 아닙니다: $pair" >&2; usage ;;
    esac
done

command -v python3 >/dev/null 2>&1 || { echo "python3가 필요합니다." >&2; exit 1; }
[ -f "$CSV_INFO_PY" ] || { echo "헬퍼 스크립트를 찾을 수 없습니다: $CSV_INFO_PY" >&2; exit 1; }

INFO_OUT="$(python3 "$CSV_INFO_PY" "$CSV_FILE")"
RANGE_LINE="$(printf '%s\n' "$INFO_OUT" | head -1)"
MODELS_LIST="$(printf '%s\n' "$INFO_OUT" | tail -n +2)"

min_date="${RANGE_LINE%%$'\t'*}"
max_date="${RANGE_LINE##*$'\t'}"

if [ -z "$min_date" ] || [ -z "$max_date" ]; then
    echo "CSV에서 날짜 범위를 계산하지 못했습니다." >&2
    exit 1
fi

start="${min_date:0:4}-${min_date:4:2}-${min_date:6:2}"
end="${max_date:0:4}-${max_date:4:2}-${max_date:6:2}"

sanitize() {
    # 원격 파일명에 문제될 수 있는 문자(공백, 슬래시)만 치환
    echo "$1" | tr ' /' '__'
}

for pair in "${PAIR_ARGS[@]}"; do
    model="${pair%%:*}"
    ver="${pair#*:}"

    if ! printf '%s\n' "$MODELS_LIST" | grep -qxF "$model"; then
        echo "경고: '${model}' 모델이 CSV에 없습니다. 계속 진행합니다." >&2
    fi

    s_model="$(sanitize "$model")"
    s_ver="$(sanitize "$ver")"

    remote_name="voc_${start}_${end}_${s_model}_${s_ver}.csv"

    if [ "$DRY_RUN" -eq 1 ]; then
        echo "[dry-run] ${remote_name}"
        continue
    fi

    echo "업로드 중: ${remote_name}"
    scp "$CSV_FILE" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/${remote_name}"
done

echo "완료"
