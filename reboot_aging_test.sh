#!/bin/bash

# STB 재부팅 에이징 테스트
#   STB uptime 이 REBOOT_UPTIME(기본 5분)이 되면 adb reboot 을 반복한다.
#   REBOOT_UPTIME 이 되기 전에 STB 가 스스로 재부팅되면 Slack 으로 알리고 종료한다.
#
# 사용법: ./reboot_aging_test.sh <STB IP>[:port]
# 환경: macOS + ADB

# Slack Incoming Webhook URL
#   환경변수 SLACK_WEBHOOK 이 없으면 스크립트 옆의 .slack_webhook 파일(git 에서 제외됨)에서 읽는다
#   예) echo 'https://hooks.slack.com/services/...' > .slack_webhook
SLACK_WEBHOOK_FILE="$(dirname "${BASH_SOURCE[0]}")/.slack_webhook"
if [ -z "${SLACK_WEBHOOK:-}" ] && [ -r "$SLACK_WEBHOOK_FILE" ]; then
    SLACK_WEBHOOK="$(head -n1 "$SLACK_WEBHOOK_FILE" | tr -d '[:space:]')"
fi
if [ -z "${SLACK_WEBHOOK:-}" ]; then
    echo "에러: Slack 웹훅 URL이 없습니다. SLACK_WEBHOOK 환경변수나 ${SLACK_WEBHOOK_FILE} 파일에 설정하세요." >&2
    exit 1
fi
REBOOT_UPTIME="${REBOOT_UPTIME:-300}"  # 5분 (초) — 이 uptime 이 되면 adb reboot
POLL_INTERVAL=5                        # uptime 확인 주기 (초)
BOOT_TIMEOUT=600                       # 10분 (초) — adb reboot 후 부팅 완료 대기 한도

if [ -z "$1" ]; then
    echo "사용법: $0 <STB IP>[:port]"
    exit 1
fi

# 포트가 없으면 기본 adb 포트(5555)를 붙인다
DEVICE="$1"
[[ "$DEVICE" == *:* ]] || DEVICE="${DEVICE}:5555"

# 스크립트 출력(adb, curl 출력 포함)을 화면과 로그 파일에 동시에 남긴다
LOG_DIR="./reboot_aging_logs"
mkdir -p "$LOG_DIR"
LOG_FILE="${LOG_DIR}/reboot_aging_${DEVICE//:/_}_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1
echo "로그 파일: ${LOG_FILE}"

REBOOT_COUNT=0

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

send_slack() {
    local message="$1"
    log "[ACTION] Slack 메시지 전송 중..."
    curl -s -X POST -H 'Content-type: application/json' \
        --data "{\"text\":\"${message}\"}" \
        "$SLACK_WEBHOOK"
    echo
    log "[OK] Slack 전송 완료"
}

is_connected() {
    [ "$(adb -s "$DEVICE" get-state 2>/dev/null)" = "device" ]
}

# 연결이 끊겨 있으면 adb connect 를 다시 시도한다
ensure_connected() {
    is_connected && return 0
    adb disconnect "$DEVICE" >/dev/null 2>&1
    adb connect "$DEVICE" >/dev/null 2>&1
    sleep 1
    is_connected
}

# 현재 uptime (초, 정수). 실패하면 빈 문자열
get_uptime() {
    adb -s "$DEVICE" shell cat /proc/uptime 2>/dev/null | awk '{ printf "%d", $1 }'
}

# 부팅마다 바뀌는 커널 boot_id. 실패하면 빈 문자열
get_boot_id() {
    adb -s "$DEVICE" shell cat /proc/sys/kernel/random/boot_id 2>/dev/null | tr -d '\r\n'
}

# 부팅 완료(sys.boot_completed=1)까지 기다린다. BOOT_TIMEOUT 을 넘기면 실패
#   인자로 이전 boot_id 를 주면 그와 다른(= 새로 부팅된) 상태가 될 때까지 기다린다
wait_boot_completed() {
    local old_boot_id="$1"
    local start=$SECONDS
    while (( SECONDS - start < BOOT_TIMEOUT )); do
        if ensure_connected && \
           [ "$(adb -s "$DEVICE" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ] && \
           { [ -z "$old_boot_id" ] || [ "$(get_boot_id)" != "$old_boot_id" ]; }; then
            return 0
        fi
        sleep "$POLL_INTERVAL"
    done
    return 1
}

# 리모컨 입력이 들어오지 않도록 리모컨 protocol 을 바꾼다 (부팅할 때마다 다시 해야 한다)
#   adb root 를 하면 adbd 가 재시작되어 연결이 끊기므로 다시 붙을 때까지 기다린다
disable_remote() {
    log "[STEP] adb root 및 리모컨 입력 차단"
    adb -s "$DEVICE" root
    local i
    for i in $(seq 1 15); do
        sleep 2
        ensure_connected && break
    done
    adb -s "$DEVICE" shell "echo 0x02 > /sys/class/remote0/amremote0/protocol"
}

report_unexpected_reboot() {
    local last_uptime="$1" new_uptime="$2"
    log "[ERROR] uptime ${REBOOT_UPTIME}초 전에 STB 재부팅 감지 (재부팅 전 uptime: ${last_uptime}초, 현재 uptime: ${new_uptime}초)"
    send_slack "[재부팅 에이징] ${DEVICE} 이슈 발생 — adb reboot 전에 STB 가 재부팅됨 (재부팅 전 uptime: ${last_uptime}초, 정상 재부팅 횟수: ${REBOOT_COUNT}회, 시각: $(date '+%Y-%m-%d %H:%M:%S'))"
    log "[EXIT] 스크립트 종료"
    exit 1
}

echo "=============================="
echo " STB 재부팅 에이징 테스트 시작"
echo "  대상: ${DEVICE}"
echo "  ${REBOOT_UPTIME}초 마다 adb reboot"
echo "=============================="

log "[INFO] STB 연결 및 부팅 완료 대기 중..."
if ! wait_boot_completed; then
    log "[ERROR] ${DEVICE} 에 연결할 수 없습니다."
    exit 1
fi

while true; do
    disable_remote
    BOOT_ID=$(get_boot_id)
    LAST_UPTIME=$(get_uptime)
    log "[INFO] 부팅 확인 (boot_id: ${BOOT_ID}, uptime: ${LAST_UPTIME}초)"

    # --- uptime 이 REBOOT_UPTIME 이 될 때까지 감시 ---
    while true; do
        sleep "$POLL_INTERVAL"

        # 연결이 끊긴 경우: 네트워크 문제일 수도 있으니 다시 붙은 뒤 boot_id 로 재부팅 여부를 판단한다
        if ! ensure_connected; then
            continue
        fi

        UPTIME=$(get_uptime)
        CUR_BOOT_ID=$(get_boot_id)
        [ -n "$UPTIME" ] || continue

        # boot_id 가 바뀌었거나 uptime 이 줄었으면 STB 가 스스로 재부팅된 것
        if { [ -n "$CUR_BOOT_ID" ] && [ -n "$BOOT_ID" ] && [ "$CUR_BOOT_ID" != "$BOOT_ID" ]; } || \
           (( UPTIME < LAST_UPTIME )); then
            report_unexpected_reboot "$LAST_UPTIME" "$UPTIME"
        fi
        LAST_UPTIME=$UPTIME

        if (( UPTIME >= REBOOT_UPTIME )); then
            break
        fi
    done

    # --- adb reboot ---
    REBOOT_COUNT=$((REBOOT_COUNT + 1))
    log "[ACTION] uptime ${UPTIME}초 — adb reboot (${REBOOT_COUNT}회차)"
    adb -s "$DEVICE" reboot

    # 새 boot_id 로 부팅 완료될 때까지 기다린다
    sleep 10
    if ! wait_boot_completed "$BOOT_ID"; then
        log "[ERROR] adb reboot 후 ${BOOT_TIMEOUT}초 동안 부팅이 완료되지 않음"
        send_slack "[재부팅 에이징] ${DEVICE} 이슈 발생 — adb reboot 후 ${BOOT_TIMEOUT}초 동안 부팅 완료되지 않음 (${REBOOT_COUNT}회차, 시각: $(date '+%Y-%m-%d %H:%M:%S'))"
        log "[EXIT] 스크립트 종료"
        exit 1
    fi
done
