#!/bin/bash

INTERVAL=600  # 10분 (600초)

# HDMI capture 장치 영상 녹화 (ffmpeg 필요)
#   캡처 장치가 연결되어 있을 때만 녹화한다. 주기마다 다시 확인하므로
#   실행 중에 장치를 꽂거나 빼도 다음 주기부터 반영된다.
#   CAPTURE_VIDEO=0 으로 실행하면 영상 녹화 없이 logcat/dmesg 만 수집한다.
#   장치 이름은 'ffmpeg -f avfoundation -list_devices true -i ""' 로 확인한다.
#   AUDIO_DEVICE=none 이면 소리 없이 영상만 녹화한다.
CAPTURE_VIDEO="${CAPTURE_VIDEO:-1}"
VIDEO_DEVICE="${VIDEO_DEVICE:-USB3.0 Video}"
AUDIO_DEVICE="${AUDIO_DEVICE:-USB3.0 Audio}"
# 이 캡처 장치는 1080p 는 최대 50fps 라서, 60Hz 출력을 프레임 손실 없이 받으려면 720p 60fps 를 쓴다
VIDEO_SIZE="${VIDEO_SIZE:-1280x720}"
VIDEO_FPS="${VIDEO_FPS:-60}"
VIDEO_BITRATE="${VIDEO_BITRATE:-8M}"   # 10분 = 약 600MB

LOGCAT_PID=""
DMESG_PID=""
VIDEO_PID=""

# ffmpeg 가 없으면 영상 녹화 없이 logcat/dmesg 만 수집한다
if [ "$CAPTURE_VIDEO" = "1" ] && ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg 가 없어 영상 녹화 없이 진행합니다. (brew install ffmpeg)"
    CAPTURE_VIDEO=0
fi

# 지금 연결된 avfoundation 장치 목록 (영상/오디오)
list_av_devices() {
    ffmpeg -hide_banner -f avfoundation -list_devices true -i "" 2>&1
}

# 목록에 해당 이름의 장치가 있는지
has_av_device() {  # has_av_device <목록> <장치 이름>
    grep -qF "] $2" <<< "$1"
}

# 이번 주기에 녹화할지 정한다 -> VIDEO_ON(1/0), VIDEO_AUDIO(오디오 장치 또는 none)
# 상태가 바뀔 때만 메시지를 띄운다
VIDEO_STATE=""
check_video_device() {
    VIDEO_ON=0
    VIDEO_AUDIO="none"
    [ "$CAPTURE_VIDEO" = "1" ] || return 0

    local devices state
    devices=$(list_av_devices)
    if ! has_av_device "$devices" "$VIDEO_DEVICE"; then
        state="none"
    else
        VIDEO_ON=1
        state="video"
        if [ "$AUDIO_DEVICE" != "none" ] && has_av_device "$devices" "$AUDIO_DEVICE"; then
            VIDEO_AUDIO="$AUDIO_DEVICE"
            state="video+audio"
        fi
    fi

    if [ "$state" != "$VIDEO_STATE" ]; then
        case "$state" in
            none)        echo "HDMI 캡처 장치 '${VIDEO_DEVICE}' 가 없어 영상 녹화 없이 진행합니다." ;;
            video)       echo "HDMI 캡처 장치 '${VIDEO_DEVICE}' 로 영상을 녹화합니다. (소리 없음)" ;;
            video+audio) echo "HDMI 캡처 장치 '${VIDEO_DEVICE}' / '${VIDEO_AUDIO}' 로 영상과 소리를 녹화합니다." ;;
        esac
        VIDEO_STATE="$state"
    fi
}

start_video() {  # start_video <파일>
    # 장치 이름으로 지정한다 (번호는 연결 순서에 따라 바뀐다)
    # 조각난(fragmented) mp4 로 저장해서 중간에 끊겨도 그때까지 녹화된 부분은 재생된다
    local audio_opts=(-c:a aac -b:a 128k)
    [ "$VIDEO_AUDIO" = "none" ] && audio_opts=(-an)
    ffmpeg -hide_banner -loglevel error -nostdin -y \
        -f avfoundation -pixel_format uyvy422 -framerate "$VIDEO_FPS" -video_size "$VIDEO_SIZE" \
        -i "${VIDEO_DEVICE}:${VIDEO_AUDIO}" \
        -c:v h264_videotoolbox -b:v "$VIDEO_BITRATE" "${audio_opts[@]}" \
        -movflags +frag_keyframe+empty_moov "$1" &
    VIDEO_PID=$!
}

# ffmpeg 는 SIGTERM 을 받으면 파일을 정상적으로 마무리하고 끝난다.
# (백그라운드 프로세스는 SIGINT 가 무시되므로 SIGTERM 을 쓴다)
# 장치가 응답하지 않아 5초 안에 안 끝나면 강제로 종료한다.
stop_video() {
    [ -n "$VIDEO_PID" ] || return 0
    kill -TERM "$VIDEO_PID" 2>/dev/null
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$VIDEO_PID" 2>/dev/null || break
        sleep 0.5
    done
    kill -0 "$VIDEO_PID" 2>/dev/null && kill -KILL "$VIDEO_PID" 2>/dev/null
    wait "$VIDEO_PID" 2>/dev/null
    VIDEO_PID=""
}

stop_logs() {
    [ -n "$LOGCAT_PID" ] && kill "$LOGCAT_PID" 2>/dev/null
    [ -n "$DMESG_PID" ]  && kill "$DMESG_PID"  2>/dev/null
    [ -n "$LOGCAT_PID" ] && wait "$LOGCAT_PID" 2>/dev/null
    [ -n "$DMESG_PID" ]  && wait "$DMESG_PID"  2>/dev/null
    LOGCAT_PID=""
    DMESG_PID=""
}

# Ctrl-C 로 끝낼 때도 녹화 파일을 마무리하고 종료한다
on_exit() {
    trap - INT TERM
    echo ""
    echo "[$(date)] Stopping..."
    stop_logs
    stop_video
    exit 0
}
trap on_exit INT TERM

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
    VIDEO_FILE="${PREFIX}_video_${TIMESTAMP}.mp4"

    check_video_device
    if [ "$VIDEO_ON" = "1" ]; then
        echo "[$(date)] Start capturing to $LOGCAT_FILE, $DMESG_FILE and $VIDEO_FILE"
    else
        echo "[$(date)] Start capturing to $LOGCAT_FILE and $DMESG_FILE"
    fi

    # 10분 동안 logcat / dmesg 수집 (+ HDMI 영상 녹화)
    # dmesg 도 -w 로 계속 받아서, 중간에 끊거나 기기가 리부팅돼도 그때까지의 로그가 남는다
    adb logcat > "$LOGCAT_FILE" &
    LOGCAT_PID=$!
    adb shell dmesg -w > "$DMESG_FILE" &
    DMESG_PID=$!
    [ "$VIDEO_ON" = "1" ] && start_video "$VIDEO_FILE"

    sleep $INTERVAL

    # logcat / dmesg / 영상 녹화 종료
    stop_logs
    stop_video

    if [ "$VIDEO_ON" = "1" ]; then
        echo "[$(date)] Saved $LOGCAT_FILE, $DMESG_FILE and $VIDEO_FILE"
    else
        echo "[$(date)] Saved $LOGCAT_FILE and $DMESG_FILE"
    fi
done
