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
    tput cnorm 2>/dev/null  # 장치 선택 메뉴에서 Ctrl-C 로 끝내도 커서를 되살린다
    echo ""
    echo "[$(date)] Stopping..."
    stop_logs
    stop_video
    exit 0
}
trap on_exit INT TERM

prompt_connect_new_device() {
    local ip
    read -rp "연결할 장치의 IP 주소를 입력하세요 (예: 192.168.0.100:5555): " ip
    if [ -z "$ip" ]; then
        echo "IP 주소가 입력되지 않았습니다." >&2
        return
    fi
    echo "==> adb connect ${ip}"
    if ! adb connect "$ip"; then
        echo "에러: adb connect에 실패했습니다: ${ip}" >&2
    fi
}

# 화살표(↑/↓) + Enter로 고르는 메뉴.
# 호출하는 쪽에서 local 배열 `options`를 준비해두면 되고,
# 결과는 ARROW_MENU_RESULT(선택된 문자열), ARROW_MENU_INDEX(선택된 인덱스)에 담긴다.
# (bash는 동적 스코프라 이 함수에서도 호출측의 local options가 그대로 보인다)
arrow_menu() {
    local count=${#options[@]}
    local sel=0
    local i key rest

    tput civis 2>/dev/null
    while true; do
        for i in "${!options[@]}"; do
            printf "\033[2K"
            if [ "$i" -eq "$sel" ]; then
                printf "  \033[7m%s\033[0m\n" "${options[$i]}"
            else
                printf "  %s\n" "${options[$i]}"
            fi
        done

        IFS= read -rsn1 key
        if [ "$key" = $'\x1b' ]; then
            IFS= read -rsn2 -t 1 rest
            key+="$rest"
        fi

        case "$key" in
            $'\x1b[A') sel=$(( (sel - 1 + count) % count )) ;;
            $'\x1b[B') sel=$(( (sel + 1) % count )) ;;
            "") break ;;
        esac

        tput cuu "$count" 2>/dev/null
    done
    tput cnorm 2>/dev/null

    ARROW_MENU_RESULT="${options[$sel]}"
    ARROW_MENU_INDEX="$sel"
}

# 로그를 받을 adb 장치를 고른다 -> ANDROID_SERIAL 로 export 해서 이후 adb 명령이 모두 이 장치를 쓴다.
#   ANDROID_SERIAL 을 지정해서 실행하면 고르지 않고 그 장치를 쓴다.
#   장치가 하나뿐이면 바로 그 장치를 쓰고, 하나도 없으면 연결될 때까지 기다린다.
select_device() {
    if [ -n "$ANDROID_SERIAL" ]; then
        echo "==> 대상 장치: ${ANDROID_SERIAL} (ANDROID_SERIAL)"
        return
    fi

    while true; do
        local devices=()
        while IFS=$'\t' read -r serial state; do
            [ -n "$serial" ] && [ "$state" = "device" ] && devices+=("$serial")
        done < <(adb devices | tail -n +2)

        if [ ${#devices[@]} -eq 0 ]; then
            echo "연결된 adb 장치가 없습니다. 장치가 연결될 때까지 기다립니다..."
            adb wait-for-device
            continue
        fi

        if [ ${#devices[@]} -eq 1 ]; then
            export ANDROID_SERIAL="${devices[0]}"
            echo "==> 대상 장치: ${ANDROID_SERIAL}"
            return
        fi

        echo ""
        echo "모델명 확인 중..."
        local labels=()
        for serial in "${devices[@]}"; do
            local model fw_version
            # 일부 빌드는 root 가 아니면 ro.vendor.fw.version 이 보이지 않는다
            adb -s "$serial" root >/dev/null 2>&1
            adb -s "$serial" wait-for-device
            model=$(adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n')
            fw_version=$(adb -s "$serial" shell getprop ro.vendor.fw.version 2>/dev/null | tr -d '\r\n')
            if [ -z "$model" ]; then
                labels+=("$serial")
            else
                labels+=("(${model})${fw_version:+ (${fw_version})} ${serial}")
            fi
        done

        echo ""
        echo "연결된 adb 장치 목록: (↑/↓ 이동, Enter 선택)"
        local options=("${labels[@]}" "새로운 장치 연결" "수집하지 않고 종료")
        arrow_menu
        local idx="$ARROW_MENU_INDEX"
        echo ""

        if [ "$idx" -lt "${#devices[@]}" ]; then
            export ANDROID_SERIAL="${devices[$idx]}"
            echo "==> 대상 장치: ${ANDROID_SERIAL}"
            return
        elif [ "$idx" -eq "${#devices[@]}" ]; then
            prompt_connect_new_device
        else
            echo "로그 수집을 취소합니다."
            exit 0
        fi
    done
}

select_device
adb root
adb wait-for-device
# 수집 시작 전에 이전 로그를 지워서 이번 실행의 로그만 남긴다
adb logcat -c

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
