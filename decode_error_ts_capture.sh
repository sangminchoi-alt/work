#!/bin/bash

# AVP_DECODER_ERROR_DECODE_ERROR 감지 테스트 스크립트
# 환경: macOS + ADB

SLACK_WEBHOOK="${SLACK_WEBHOOK:?환경변수 SLACK_WEBHOOK을 설정하세요}"
TARGET_LOG="AVP_DECODER_ERROR_DECODE_ERROR"
MONITOR_DURATION=1800  # 30분 (초) — 미발생 시 루프 재시작 기준
POST_DETECT_DELAY=180  # 3분 (초) — 감지 후 대기 시간

echo "=============================="
echo " AVP Decoder Error 모니터 시작"
echo "=============================="

# ADB root 권한 획득
echo "[INFO] adb root 실행 중..."
adb root
sleep 2

adb shell "echo 0x02 > /sys/class/remote0/amremote0/protocol"

while true; do
    echo ""
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] 루프 시작"

    # --- 초기화 ---
    echo "[STEP 1] dumpts=0 설정 및 임시 파일 삭제"
    adb shell setprop vendor.amtsplayer.dumpts 0
    adb shell rm -rf /data/tmp/*
    adb shell input keyevent KEYCODE_0
    echo "[WAIT] 10초 대기..."
    sleep 10

    # --- 채널 변경 ---
    echo "[STEP 2] dumpts=1 설정 및 채널 5 입력"
    adb shell setprop vendor.amtsplayer.dumpts 1
    adb shell input keyevent KEYCODE_5
    echo "[WAIT] 10초 대기..."
    sleep 10

    # --- 로그 모니터링 ---
    echo "[MONITOR] logcat 모니터링 시작 (최대 ${MONITOR_DURATION}초)..."

    adb logcat -c
    TMP_LOG=$(mktemp ./avp_logcat_XXXXXXXX)
    adb logcat > "$TMP_LOG" &
    LOGCAT_PID=$!

    DETECTED=false
    ELAPSED=0
    CHECK_INTERVAL=5

    while [ $ELAPSED -lt $MONITOR_DURATION ]; do
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))

        if grep -q "$TARGET_LOG" "$TMP_LOG" 2>/dev/null; then
            DETECTED=true
            echo ""
            echo "[!!!] ${TARGET_LOG} 감지됨! (경과: ${ELAPSED}초)"
            echo "[WAIT] ${POST_DETECT_DELAY}초(3분) 대기 후 처리 시작..."
            sleep $POST_DETECT_DELAY  # ← 감지 시점부터 3분 대기
            break
        fi

        # 진행 상황 출력 (60초마다)
        if [ $((ELAPSED % 60)) -eq 0 ]; then
            echo "[MONITOR] 경과: ${ELAPSED}초 / ${MONITOR_DURATION}초 — 이상 없음"
        fi
    done

    # logcat 프로세스 종료
    kill $LOGCAT_PID 2>/dev/null
    wait $LOGCAT_PID 2>/dev/null

    # --- 결과 처리 ---
    if [ "$DETECTED" = true ]; then

        # --- 로그 파일 수집 ---
        LOG_DIR="./avp_logs_$(date '+%Y%m%d_%H%M%S')"
        mkdir -p "$LOG_DIR"
        echo "[LOG] 로그 파일 수집 중... → ${LOG_DIR}"

        # 1) 감지된 logcat 전체 저장
        cp "$TMP_LOG" "${LOG_DIR}/logcat_full.txt"

        # 2) 에러 라인만 별도 추출
        grep "$TARGET_LOG" "$TMP_LOG" > "${LOG_DIR}/logcat_errors_only.txt"

        # 3) /data/tmp/ 내 덤프 파일 pull
        echo "[LOG] /data/tmp/ 덤프 파일 수집 중..."
        adb pull /data/tmp/ "${LOG_DIR}/device_tmp/" 2>/dev/null \
            && echo "[LOG] /data/tmp/ pull 완료" \
            || echo "[WARN] /data/tmp/ pull 실패 또는 파일 없음"

        # 4) 감지 시점 이후 추가 로그 덤프
        adb logcat -d > "${LOG_DIR}/logcat_dump_at_detect.txt" 2>/dev/null

        # 5) 임시 파일 삭제
        rm -f "$TMP_LOG"

        # 6) 수집 완료 메시지
        echo "[LOG] 수집 완료:"
        ls -lh "$LOG_DIR"

        # --- Slack 메시지 전송 ---
        echo "[ACTION] Slack 메시지 전송 중..."
        MESSAGE="${TARGET_LOG} 발생 — 로그: ${LOG_DIR}"
        curl -s -X POST -H 'Content-type: application/json' \
            --data "{\"text\":\"${MESSAGE}\"}" \
            "$SLACK_WEBHOOK"
        echo "[OK] Slack 전송 완료"

        # --- dumpts=0 설정 ---
        echo "[STEP] dumpts=0 설정"
        adb shell setprop vendor.amtsplayer.dumpts 0

        echo "[EXIT] 스크립트 종료"
        exit 0
    else
        rm -f "$TMP_LOG"
        echo "[INFO] ${MONITOR_DURATION}초 동안 에러 미발생 — 루프 재시작"
    fi

done