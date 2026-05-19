#!/bin/bash

INTERVAL=600  # 10분 (600초)

adb root

while true
do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    LOGCAT_FILE="logcat_${TIMESTAMP}.txt"
    DMESG_FILE="dmesg_${TIMESTAMP}.txt"

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
