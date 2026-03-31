#!/bin/bash

export LC_ALL=C
export LANG=C

if [ $# -lt 1 ]; then
    echo "사용법: $0 <logfile> [keycode]"
    exit 1
fi

LOGFILE="$1"
KEYCODE="${2:-19}"
FILTERED_LOG="${LOGFILE%.*}_filtered.log"

if [ ! -f "$LOGFILE" ]; then
    echo "파일이 없습니다: $LOGFILE"
    exit 1
fi

echo "원본 로그: $LOGFILE"
echo "필터 로그: $FILTERED_LOG"

grep -E "interceptKeyTi keyCode=${KEYCODE} down=false|HLSPlaybackEvent.*onRenderedFirstFrame" "$LOGFILE" > "$FILTERED_LOG"

awk -v keycode="$KEYCODE" '
function to_ms(ts,   a,h,m,s,ms,sec) {
    split(ts, a, /[:.]/)
    h  = a[1] + 0
    m  = a[2] + 0
    s  = a[3] + 0
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
' "$FILTERED_LOG"