#!/bin/bash

export LC_ALL=C
export LANG=C

COUNT=100
KEYCODE=19
INTERVAL=10

# 📌 파일명: 현재 시간 기반
START_TIME=$(date +"%Y%m%d_%H%M%S")
MODEL_NAME=$(adb shell getprop ro.product.model)
VERSION_NAME=$(adb shell cat system/usr/skb/version.txt)
LOGFILE="./zapping_test_${MODEL_NAME}_${VERSION_NAME}_${START_TIME}.log"

adb root
adb shell "echo 0x02 > /sys/class/remote0/amremote0/protocol"

echo "logcat 초기화"
adb logcat -c

echo "로그 파일: $LOGFILE"
echo "logcat 수집 시작"

adb logcat -v time > "$LOGFILE" &
LOGCAT_PID=$!

sleep 1

echo "키 입력 ${COUNT}회 시작"
for ((i=1; i<=COUNT; i++)); do
    echo "[$i/$COUNT] KEYCODE_DPAD_UP"
    adb shell input keyevent "$KEYCODE"
    sleep "$INTERVAL"
done

echo "로그 마무리 대기"
sleep 10

kill "$LOGCAT_PID" 2>/dev/null
wait "$LOGCAT_PID" 2>/dev/null

echo "로그 분석 시작"

awk -v keycode="$KEYCODE" '
function to_ms(ts,   h,m,s,a,sec) {
    split(ts, a, /[:.]/)
    h = a[1] + 0
    m = a[2] + 0
    s = a[3] + 0
    ms = a[4] + 0
    sec = h * 3600 + m * 60 + s
    return sec * 1000 + ms
}

$0 ~ ("interceptKeyTi keyCode=" keycode " down=false") {
    key_ts = to_ms($2)
    waiting = 1
    next
}

waiting && $0 ~ /HLSPlaybackEvent.*onRenderedFirstFrame/ {
    frame_ts = to_ms($2)
    diff = frame_ts - key_ts

    if (diff < 0) {
        diff += 24 * 3600 * 1000
    }

    count++
    total += diff
    results[count] = diff

    printf("[%d] %d ms\n", count, diff)

    waiting = 0
}

END {
    print "===================="
    print "성공:", count

    if (count > 0) {
        avg = total / count
        print "평균:", int(avg), "ms"

        min = results[1]
        max = results[1]
        for (i = 1; i <= count; i++) {
            if (results[i] < min) min = results[i]
            if (results[i] > max) max = results[i]
        }
        print "최소:", min, "ms"
        print "최대:", max, "ms"
    } else {
        print "매칭된 결과 없음"
    }
}
' "$LOGFILE"

echo ""
echo "📄 로그 저장 위치: $LOGFILE"