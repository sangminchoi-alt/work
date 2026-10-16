#!/bin/bash

INTERVAL=600  # 10분 (600초)

adb root
adb wait-for-device

# getprop 값을 파일명에 쓸 수 있게 정리 (CR 제거, 공백/'/' 는 '_', 없으면 unknown)
get_prop() {
    local value
    value=$(adb shell getprop "$1" 2>/dev/null | tr -d '\r\n' | tr ' /' '__')
    echo "${value:-unknown}"
}

while true
do
    # 펌웨어 업그레이드로 버전이 바뀔 수 있어 매번 다시 읽는다
    MODEL=$(get_prop ro.product.model)
    VERSION=$(get_prop ro.vendor.fw.version)
    PREFIX="${MODEL}_${VERSION}"

    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGCAT_FILE="${PREFIX}_logcat_${TIMESTAMP}.txt"
    DMESG_FILE="${PREFIX}_dmesg_${TIMESTAMP}.txt"

    echo "[$(date)] Start capturing to $LOGCAT_FILE and $DMESG_FILE"

    # 10분 동안 logcat 수집
    adb logcat > "$LOGCAT_FILE" &
    LOGCAT_PID=$!

    sleep $INTERVAL

    # logcat 종료
    kill $LOGCAT_PID
    wait $LOGCAT_PID 2>/dev/null

    # dmesg 수집
    adb shell dmesg > "$DMESG_FILE"

    echo "[$(date)] Saved $LOGCAT_FILE and $DMESG_FILE"
done
