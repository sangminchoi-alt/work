#!/bin/bash
# Daily aging FTP 서버에서 시료별 skbtv_meminfo 로그를 기간을 정해 다운로드한다.
#
#   서버 구조: <BASE_URL>/<YYYY-MM-DD>_daily_a_net/<시료번호>/memory/skbtv_meminfo_YYYYMMDD_HHMMSS.log
#   저장 구조: <OUT_DIR>/<시료번호>/skbtv_meminfo_*.log   (skbtv_memory_report.py 입력과 같은 구조)
#
# 사용법:
#   ./download_skbtv_meminfo.sh -s "2026-11-13 10:00" -e "2026-11-16 10:00" [옵션] [시료번호 ...]
#
# 예) 12대 시료 지정 (samples.txt 가 없을 때. 실행 후 <저장 폴더>/samples.txt 가 생긴다)
#   ./download_skbtv_meminfo.sh -s "2026-11-13 10:00" -e "2026-11-16 10:00" S202512080520056 S202512080520057 S202512080520059 S202512080520061 S202512081520047 S202512081520070 GZ2503088N180082 GZ2503088N180086 GZ2505034N270024 GZ2505034N270045 GZ2505034N270046 GZ2505035N270045
# 예) samples.txt 가 있을 때 (시료번호 생략)
#   ./download_skbtv_meminfo.sh -s "2026-11-13 10:00" -e "2026-11-16 10:00"
#
# 옵션:
#   -s 시작 시각   KST, "YYYY-MM-DD HH:MM" (필수)
#   -e 종료 시각   KST, "YYYY-MM-DD HH:MM" (필수, 이 시각 파일까지 포함)
#   -o 저장 폴더   기본: 스크립트 옆 skbtv
#   -l 시료 목록   한 줄에 시료번호 하나. 시료번호를 인자로 주지 않으면 사용.
#                  기본: <저장 폴더>/samples.txt
#   -j 동시 다운로드 시료 수 (기본 4)
#   -b 서버 경로   기본: ftp://altserver01.iptime.org/Aging/AI5/daily_aging
#   -r             다운로드 후 skbtv_memory_report.py 로 그래프 HTML 생성
#
# 계정: FTP_USER / FTP_PASSWORD 환경변수, 없으면 스크립트 옆 .ftp_credentials (git 에서 제외됨)
# 이미 받은 파일은 서버와 크기가 같으면 건너뛰므로, 중간에 끊겨도 같은 명령으로 다시 실행하면 이어 받는다.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="ftp://altserver01.iptime.org/Aging/AI5/daily_aging"
FOLDER_SUFFIX="_daily_a_net"
OUT_DIR="$SCRIPT_DIR/skbtv"
START="" END="" LIST="" JOBS=4 REPORT=0

usage() { awk 'NR > 1 && !/^#/ { exit } NR > 1 { sub(/^# ?/, ""); print }' "$0"; exit "${1:-1}"; }

while getopts "s:e:o:l:j:b:rh" opt; do
    case $opt in
        s) START=$OPTARG ;; e) END=$OPTARG ;; o) OUT_DIR=$OPTARG ;; l) LIST=$OPTARG ;;
        j) JOBS=$OPTARG ;; b) BASE_URL=${OPTARG%/} ;; r) REPORT=1 ;; h) usage 0 ;; *) usage ;;
    esac
done
shift $((OPTIND - 1))
[ -n "$START" ] && [ -n "$END" ] || { echo "에러: -s 시작 시각과 -e 종료 시각이 필요합니다." >&2; usage; }

if [ -z "${FTP_USER:-}" ] || [ -z "${FTP_PASSWORD:-}" ]; then
    if [ -r "$SCRIPT_DIR/.ftp_credentials" ]; then
        source "$SCRIPT_DIR/.ftp_credentials"  # FTP_USER, FTP_PASSWORD
    fi
fi
[ -n "${FTP_USER:-}" ] && [ -n "${FTP_PASSWORD:-}" ] || {
    echo "에러: FTP 계정이 없습니다. FTP_USER/FTP_PASSWORD 환경변수나 $SCRIPT_DIR/.ftp_credentials 에 설정하세요." >&2
    echo "      (.ftp_credentials.example 참고)" >&2; exit 1; }

# "YYYY-MM-DD HH:MM[:SS]" -> YYYYMMDDHHMMSS
to_ts() {
    local d t
    d=$(echo "$1" | awk '{print $1}'); t=$(echo "$1" | awk '{print $2}')
    [[ $d =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || { echo "에러: 시각 형식이 잘못됐습니다: $1" >&2; exit 1; }
    [ -z "$t" ] && t="00:00"
    [[ $t =~ ^[0-9]{2}:[0-9]{2}$ ]] && t="$t:00"
    [[ $t =~ ^[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || { echo "에러: 시각 형식이 잘못됐습니다: $1" >&2; exit 1; }
    echo "${d//-/}${t//:/}"
}
START_TS=$(to_ts "$START") || exit 1
END_TS=$(to_ts "$END") || exit 1
[ "$START_TS" \< "$END_TS" ] || [ "$START_TS" = "$END_TS" ] || { echo "에러: 시작 시각이 종료 시각보다 늦습니다." >&2; exit 1; }

# 시작~종료 날짜 목록 (macOS / Linux date 모두 지원)
next_day() {
    if date -j -f %Y-%m-%d "$1" +%Y-%m-%d >/dev/null 2>&1; then
        date -j -v+1d -f %Y-%m-%d "$1" +%Y-%m-%d
    else
        date -d "$1 +1 day" +%Y-%m-%d
    fi
}
DATES=()
d="${START_TS:0:4}-${START_TS:4:2}-${START_TS:6:2}"
last="${END_TS:0:4}-${END_TS:4:2}-${END_TS:6:2}"
while :; do
    DATES+=("$d")
    [ "$d" = "$last" ] && break
    d=$(next_day "$d") || exit 1
    [ ${#DATES[@]} -gt 400 ] && { echo "에러: 기간이 너무 깁니다." >&2; exit 1; }
done

# 시료 목록
mkdir -p "$OUT_DIR" || exit 1
SAMPLES=("$@")
if [ ${#SAMPLES[@]} -eq 0 ]; then
    [ -n "$LIST" ] || LIST="$OUT_DIR/samples.txt"
    [ -r "$LIST" ] || { echo "에러: 시료번호를 인자로 주거나 -l 목록 파일을 지정하세요 ($LIST 없음)." >&2; exit 1; }
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(echo "$line" | tr -d '[:space:]')
        [ -n "$line" ] && [ "${line:0:1}" != "#" ] && SAMPLES+=("$line")
    done < "$LIST"
fi
[ ${#SAMPLES[@]} -gt 0 ] || { echo "에러: 시료가 없습니다." >&2; exit 1; }
# 그래프 색 순서를 맞추기 위해 시료 순서를 저장 폴더에 남긴다
printf '%s\n' "${SAMPLES[@]}" > "$OUT_DIR/samples.txt.tmp" && mv "$OUT_DIR/samples.txt.tmp" "$OUT_DIR/samples.txt"

echo "기간: $START ~ $END (KST) · 날짜 폴더 ${#DATES[@]}개 · 시료 ${#SAMPLES[@]}개 → $OUT_DIR"

download_sample() {
    local S=$1 d url raw rc err list n=0 skip=0 fail=0 size f local_size
    local -a args
    mkdir -p "$OUT_DIR/$S"
    err=$(mktemp)
    for d in $DATES_STR; do
        url="$BASE_URL/${d}${FOLDER_SUFFIX}/$S/memory/"
        raw=$(curl -sS --max-time 60 --retry 2 --user "${FTP_USER}:${FTP_PASSWORD}" "$url" 2>"$err"); rc=$?
        if [ $rc -ne 0 ]; then
            case $rc in
                9|78) echo "  $S: $d 폴더 없음 ($url)" ;;   # 서버에 해당 날짜/시료 폴더가 없음
                *) echo "  $S: $d 목록 조회 실패 (curl $rc: $(head -n1 "$err"))"; fail=1 ;;
            esac
            continue
        fi
        # mawk 등 {n} 반복을 지원하지 않는 awk 도 있으므로 TS_RE 는 [0-9] 를 나열해 쓴다
        list=$(printf '%s\n' "$raw" | tr -d '\r' |
            awk -v s="$START_TS" -v e="$END_TS" -v re="$TS_RE" '$NF ~ /^skbtv_meminfo_/ {
                f = $NF; if (match(f, re)) { t = substr(f, RSTART, 8) substr(f, RSTART + 9, 6);
                if (t >= s && t <= e) print $5, f } }')
        [ -z "$list" ] && continue
        args=()
        while read -r size f; do
            n=$((n + 1))
            if [ -f "$OUT_DIR/$S/$f" ]; then
                local_size=$(wc -c < "$OUT_DIR/$S/$f" | tr -d ' ')
                [ "$local_size" = "$size" ] && { skip=$((skip + 1)); continue; }
            fi
            args+=(-o "$OUT_DIR/$S/$f" "$url$f")
        done <<< "$list"
        if [ ${#args[@]} -gt 0 ]; then
            curl -sS --max-time 3600 --retry 3 --user "${FTP_USER}:${FTP_PASSWORD}" "${args[@]}" || fail=1
        fi
    done
    rm -f "$err"
    if [ $fail -ne 0 ]; then
        echo "  $S: 일부 실패 (같은 명령으로 다시 실행하면 이어 받습니다)"
    else
        echo "  $S: ${n}개 (기존 ${skip}개 건너뜀)"
    fi
    [ $n -gt 0 ] || echo "  $S: 경고 - 범위 안에 파일이 없습니다 (시료번호/기간 확인)"
}
TS_RE='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]_[0-9][0-9][0-9][0-9][0-9][0-9]'
export -f download_sample
export BASE_URL FOLDER_SUFFIX OUT_DIR START_TS END_TS FTP_USER FTP_PASSWORD TS_RE
export DATES_STR="${DATES[*]}"

printf '%s\n' "${SAMPLES[@]}" | xargs -P "$JOBS" -I{} bash -c 'download_sample "$1"' _ {}

# 결과 확인: 시료별 범위 안 파일 수
echo "다운로드 결과:"
for S in "${SAMPLES[@]}"; do
    cnt=$(ls "$OUT_DIR/$S" 2>/dev/null | awk -v s="$START_TS" -v e="$END_TS" -v re="$TS_RE" '{
        if (match($0, re)) { t = substr($0, RSTART, 8) substr($0, RSTART + 9, 6); if (t >= s && t <= e) c++ } } END { print c + 0 }')
    echo "  $S: $cnt"
done

if [ $REPORT -eq 1 ]; then
    python3 "$SCRIPT_DIR/skbtv_memory_report.py" "$OUT_DIR" --start "$START" --end "$END" \
        -o "$SCRIPT_DIR/skbtv_report/skbtv_memory_trend.html"
fi
