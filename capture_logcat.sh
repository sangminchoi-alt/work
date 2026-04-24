#!/bin/bash

INTERVAL=600  # 10분 (600초)

while true
do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    FILENAME="logcat_${TIMESTAMP}.txt"

    echo "[$(date)] Start capturing to $FILENAME"

    # 10분 동안 logcat 수집
    adb logcat > "$FILENAME" &
    LOGCAT_PID=$!

    sleep $INTERVAL

    # logcat 종료
    kill $LOGCAT_PID
    wait $LOGCAT_PID 2>/dev/null

    echo "[$(date)] Saved $FILENAME"
done
