#!/bin/zsh

COLOR_RED="1;31"
COLOR_GREEN="1;32"

SUBLIME_TEXT="/Users/tonight0210/Downloads/subl"
ANDROID_KEYCODE_STRINGS=$(grep 'public static final int KEYCODE' ~/Downloads/work/KeyEvent.java | sed 's/public static final int //g')

get_android_property_by_key() {
    local file_path="getprop.txt"
    local input_key="$1"

    local value=$(grep "^\\[${input_key}\\]" "$file_path" | sed -E "s/^\\[${input_key}\\]: \\[(.*)\\]/\\1/g")

    if [ -z "$value" ]; then
        echo "NULL"
    else
        echo "$value"
    fi
}

get_xml_property_by_key() {
    local file_path="$1"
    local input_key="$2"

    local value=$(grep "<entry key=\"$input_key\">" "$file_path" | sed -E 's/.*<entry key="'$input_key'">(.*)<\/entry>.*/\1/g')

    if [ -z "$value" ]; then
        echo "NULL"
    else
        echo "$value"
    fi
}

display_stb_on_property() {
    local STB_ON=$(get_android_property_by_key sys.stb.on)
    if [ "$STB_ON" -eq 1 ]; then COLOR=${COLOR_GREEN};STB_ON="Wake Up"; else COLOR=${COLOR_RED};STB_ON="Sleep"; fi
    echo "======================================================="
    echo -e "STB ON/OFF\t: \033[${COLOR}m"$STB_ON"\033[0m"
    echo "======================================================="
    echo ""
}

display_tv_power_control_property() {
    local TV_POWER_CONTROL=$(get_xml_property_by_key tvservice-system-properties.xml TV_POWER_CONTROL)
    if [ "$TV_POWER_CONTROL" -eq 1 ]; then COLOR=${COLOR_GREEN};TV_POWER_CONTROL="사용함"; else COLOR=${COLOR_RED};TV_POWER_CONTROL="사용안함"; fi
    echo "======================================================="
    echo -e "TV전원제어\t: \033[${COLOR}m"$TV_POWER_CONTROL"\033[0m"
    echo "======================================================="
    echo ""
}

display_tv_information() {
    if [ ! -e hdmi-edid.xml ]; then echo -e "\033[${COLOR_RED}mhdmi-edid.xml 파일이 없습니다!!\033[0m";echo "";return; fi

    local input_xml=`cat hdmi-edid.xml | grep "<hdmi_edid"`
    local model_name=$(echo "$input_xml" | sed -n 's/.*model_name="\([^"]*\)".*/\1/p')
    local manufacturer_id=$(echo "$input_xml" | sed -n 's/.*manufacturer_id="\([^"]*\)".*/\1/p')
    local manufacture_date=$(echo "$input_xml" | sed -n 's/.*manufacture_date="\([^"]*\)".*/\1/p')
    local edid_hex=$(xml sel -t -v //edid_hex -nl hdmi-edid.xml | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    local hdmi_port=$(echo "$edid_hex" | sed -n 's/.*030c00\([0-9a-f]\).*/\1/p')
    
    echo "======================================================="
    echo -e "TV 제조사\t: $manufacturer_id"
    echo -e "TV 모델명\t: $model_name"
    echo -e "TV 제조년월\t: $manufacture_date"
    echo -e "HDMI Port\t: $hdmi_port"
    echo "======================================================="
    echo ""
}

check_video_resolution_low() {
    local low_video_resolution=$(grep -rn 'ORes\[1280x720\]' merged_main.log | head -1)
    local display_resolution=$(get_xml_property_by_key tvservice-setting-properties.xml DISPLAY_RESOLUTION)

    if [ -z "$low_video_resolution" ]; then return; fi
    if [ "$display_resolution" = "1" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "화면 해상도 저하 이슈"
    echo ""
    echo -e "\033[${COLOR}m"$low_video_resolution"\033[0m"
    echo "======================================================="
    echo ""
}

display_stb_screen_settings() {
    local display_resolution=$(get_xml_property_by_key tvservice-setting-properties.xml DISPLAY_RESOLUTION)
    if [ "$display_resolution" = "11" ]; then display_resolution="자동"; fi
    if [ "$display_resolution" = "10" ]; then display_resolution="2160p(4K/UHD)"; fi
    if [ "$display_resolution" = "5" ]; then display_resolution="1080p"; fi
    if [ "$display_resolution" = "3" ]; then display_resolution="1080i"; fi
    if [ "$display_resolution" = "1" ]; then display_resolution="720p"; fi

    local VIDEO_BRIGHTNESS=$(get_xml_property_by_key tvservice-setting-properties.xml VIDEO_BRIGHTNESS)
    local VIDEO_CONTRAST=$(get_xml_property_by_key tvservice-setting-properties.xml VIDEO_CONTRAST)
    local VIDEO_SATURATION=$(get_xml_property_by_key tvservice-setting-properties.xml VIDEO_SATURATION)
    local VIDEO_HUE=$(get_xml_property_by_key tvservice-setting-properties.xml VIDEO_HUE)

    echo "======================================================="
    echo -e "설정 > 시청환경 > 화면/음향 설정"
    echo -e "화면 해상도\t: $display_resolution"
    echo -e "밝기\t\t: $VIDEO_BRIGHTNESS"
    echo -e "명암\t\t: $VIDEO_CONTRAST"
    echo -e "선명도\t\t: $VIDEO_SATURATION"
    echo -e "색상\t\t: $VIDEO_HUE"
    echo "======================================================="
    echo ""

    check_video_resolution_low
    check_VPPDBG_message
}

display_stb_startscreen_settings() {
    local start_screen=$(get_xml_property_by_key tvservice-system-properties.xml PROPERTY_START_SCREEN)
    if [ "$start_screen" = "0" ]; then start_screen="B tv 홈"; fi
    if [ "$start_screen" = "1" ]; then start_screen="실시간 TV"; fi
    if [ "$start_screen" = "4" ]; then start_screen="해피시니어"; fi

    echo "======================================================="
    echo -e "설정 > 사용자 맞춤 설정 > 시작화면 설정"
    echo -e "시작화면 설정\t: $start_screen"
    echo "======================================================="
    echo ""
}

display_rcu_iset_information() {
    local ISET_CODE=$(get_android_property_by_key dev.rcu.iset_code)
    local ISET_TYPE=$(get_android_property_by_key dev.rcu.iset_type)
    if [ "$ISET_CODE" = "0x00e2" ]; then ISET_CODE=${ISET_CODE}"\t삼성"; fi
    if [ "$ISET_CODE" = "0x00e3" ]; then ISET_CODE=${ISET_CODE}"\tLG"; fi
    if [ "$ISET_TYPE" = "0x00" ]; then ISET_TYPE=${ISET_TYPE}"\t\t자동동조"; fi
    if [ "$ISET_TYPE" = "0x01" ]; then ISET_TYPE=${ISET_TYPE}"\t\t수동동조"; fi
    if [ "$ISET_TYPE" = "0x02" ]; then ISET_TYPE=${ISET_TYPE}"\t\t학습동조"; fi
    echo "======================================================="
    echo "TV 동조코드 : https://ucyber.skbroadband.com:8443/faq/tv_sympathy_code_table.html"
    echo "TV 동조설정 : 0x00(자동동조), 0x01(수동동조), 0x02(학습동조)"
    echo ""
    echo -e "ISET CODE\t: $ISET_CODE"
    echo -e "ISET TYPE\t: $ISET_TYPE"
    echo "======================================================="
    echo ""
}

display_rcu_information() {
    local rcu=`cat getprop.txt | grep "sys.skb.btsvc.rcu\|sys.skb.isqms.btsvc.rcu"`
    echo "======================================================="
    echo "RCU 페어링 정보"
    echo ""
    echo "$rcu"
    echo "======================================================="
    echo ""
}

display_audio_output_path() {
    local AUDIO_OUTPUT_PATH=$(get_android_property_by_key sys.stb.audio.paththrough)
    if [ "$AUDIO_OUTPUT_PATH" -eq 1 ]; then COLOR=${COLOR_GREEN};AUDIO_OUTPUT_PATH="B tv"; else COLOR=${COLOR_RED};AUDIO_OUTPUT_PATH="외부입력"; fi
    echo "======================================================="
    echo -e "음향출력\t: \033[${COLOR}m"$AUDIO_OUTPUT_PATH"\033[0m"
    echo "======================================================="
    echo ""

    check_R4001_createTrack
}

display_volume_level() {
    local VOLUME_LEVEL=$(get_android_property_by_key persist.sys.audio.last_volume)
    echo "======================================================="
    echo -e "Volume level\t: $VOLUME_LEVEL"
    echo "======================================================="
    echo ""    
}

display_channel_information() {
    CHANNEL_NUMBER=$(get_xml_property_by_key tvservice-system-properties.xml CHANNELNUM)
    CHANNEL_NAME=$(get_xml_property_by_key tvservice-system-properties.xml CHANNELNAME)
    if [ "$CHANNEL_NAME" = "NULL" ]; then CHANNEL_NAME="채널정보 없음"; fi
    echo "======================================================="
    echo -e "Channel Number\t: $CHANNEL_NUMBER"
    echo -e "Channel Name\t: $CHANNEL_NAME"
    echo "======================================================="
    echo ""
}

display_uptime() {
    UPTIME=`cat uptime.txt`
    echo "======================================================="
    echo "$UPTIME"
    echo "======================================================="
    echo ""
}

display_front_mic_on_off() {
    FRONT_MIC_ON_OFF=$(get_xml_property_by_key tvservice-system-properties.xml NUGU_MIC_ONOFF)
    if [ "$FRONT_MIC_ON_OFF" -eq 1 ]; then COLOR=${COLOR_GREEN};FRONT_MIC_ON_OFF="FFV 음성인식 ON"; else COLOR=${COLOR_RED};FRONT_MIC_ON_OFF="FFV 음성인식 OFF"; fi
    echo "======================================================="
    echo -e "아리아 음성인식\t: \033[${COLOR}m"$FRONT_MIC_ON_OFF"\033[0m"
    echo "======================================================="
    echo ""    
}

open_tombstone_files() {
    local FINGERPRINT=$(get_android_property_by_key ro.build.fingerprint)
    setopt null_glob
    for file in tombstone*; do
        if [ -f "$file" ]; then
            check_fingerprint=`cat $file | grep $FINGERPRINT`
            if [ ! -z $check_fingerprint ]; then $SUBLIME_TEXT $file; fi
        fi
    done
    unsetopt null_glob
}

display_audio_delay() {
    local AUDIO_DELAY=$(get_xml_property_by_key tvservice-system-properties.xml BTVAUDIO_DELAY_OFFSET)
    if [ "$AUDIO_DELAY" -eq 0 ]; then COLOR=${COLOR_RED}; else COLOR=${COLOR_GREEN}; fi
    echo "======================================================="
    echo -e "음향지연설정\t: \033[${COLOR}m"$AUDIO_DELAY"\033[0m"
    echo "======================================================="
    echo ""        
}

display_stb_mac_address() {
    local MAC_ADDRESS=$(cat qsm_init_data.json | jq -r '.mac_address')
    echo "======================================================="
    echo -e "Mac Address\t: $MAC_ADDRESS"
    echo "======================================================="
    echo "" 
    echo $MAC_ADDRESS | pbcopy
}

get_keycode_string() {
    keycode_string=$(echo "$ANDROID_KEYCODE_STRINGS" | awk -v num="$1" -F' = ' '$2 == num";" {sub(/^[ \t]+/, "", $1); print $1}')

    if [ -n "$keycode_string" ]; then
        echo "$keycode_string"
    else
        echo "Unknown keycode"
    fi
}

display_keycode_history() {
    local history_onkey=$(grep -n 'onKeyDown keyCode' merged_main.log)
    local history_stb=$(grep -n 'STBGlobalkeyBroadCastReceiver.*onReceive.*keyCode.*ACTION_DOWN' merged_main.log)
    local history=$(printf '%s\n%s\n' "$history_onkey" "$history_stb" | grep -v '^$' | sort -t: -k1,1n)
    if [ -z "$history" ]; then return; fi
    echo "======================================================="
    echo -e "Keycode History"
    echo ""

    IFS=$'\n' log_entries=("${(@f)history}")
    for entry in "${log_entries[@]}"; do
        timestamp=$(echo "$entry" | grep -oE '[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}')

        if echo "$entry" | grep -q 'STBGlobalkeyBroadCastReceiver'; then
            keycode=$(echo "$entry" | awk -F 'keyCode : ' '{print $2}' | awk -F',' '{print $1}' | tr -cd '0-9')
        else
            keycode=$(echo "$entry" | awk -F 'keyCode = ' '{print $2}' | awk '{print $1}' | tr -cd '0-9')
        fi

        echo -e "$timestamp\t$keycode\t$(get_keycode_string $keycode)"
    done

    echo "======================================================="
    echo ""
}

check_video_freezing() {
    local VIDEO_FREEZE=$(grep -rn 'no EOP at EOS' merged_main.log)

    if [ -z "$VIDEO_FREEZE" ]; then return; fi

    echo "======================================================="
    echo -e "no EOP at EOS (BTVV-3906 / BPM-9053 화면 끊김 가능성)"
    echo ""
    echo -e "$VIDEO_FREEZE"
    echo "======================================================="
    echo ""
}

check_nugu_broadcast_receiver() {
    local NUGU_BROADCAST_RECEIVER=$(grep -rn 'mNUGUBroadCastReceiver() called - CtrlType' merged_main.log)

    if [ -z "$NUGU_BROADCAST_RECEIVER" ]; then return; fi

    echo "======================================================="
    echo -e "mNUGUBroadCastReceiver (BTVSBOX-636 [VoC] 화면 나오지 않고, 소리만 나오는 VoC 개선 건)"
    echo ""
    echo -e "$NUGU_BROADCAST_RECEIVER"
    echo "======================================================="
    echo ""
}

check_memtrack_page_allocation_failure() {
    local MEMTRACK_PAGE_ALLOCATION_FAILURE=$(grep 'memtrack@1.0-se: page allocation failure' dmesg.txt)

    if [ -z "$MEMTRACK_PAGE_ALLOCATION_FAILURE" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "\033[${COLOR}m"$MEMTRACK_PAGE_ALLOCATION_FAILURE"\033[0m"
    echo "======================================================="
    echo ""
}

check_pushAmpBD_failed() {
    local PUSH_AMP_BD_FAILED=$(grep -rn 'pushAmpBD failed' merged_main.log | head -1)

    if [ -z "$PUSH_AMP_BD_FAILED" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "pushAmpBD failed (오디오 관련 VoC)"
    echo ""
    echo -e "\033[${COLOR}m"$PUSH_AMP_BD_FAILED"\033[0m"
    echo "======================================================="
    echo ""
}

check_VideoReleaseThread() {
    local VIDEO_RELEASE_THREAD_MESSAGE=$(grep -rn 'VideoReleaseThread' merged_main.log)

    if [ -z "$VIDEO_RELEASE_THREAD_MESSAGE" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "VideoReleaseThread 에러메세지 (BTVV-7613 동행점검 건)"
    echo ""
    echo -e "\033[${COLOR}m"$VIDEO_RELEASE_THREAD_MESSAGE"\033[0m"
    echo "======================================================="
    echo ""
}

check_VPPDBG_message() {
    local VPPDBG_COUNT_MESSAGE=$(grep -rn 'VPPDBG:UF:Count' merged_main.log | head -5)

    if [ -z "$VPPDBG_COUNT_MESSAGE" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "\033[${COLOR}mVPPDBG:UF:Count 에러메세지 (화면 깜박임 이슈)\033[0m"
    echo ""
    echo -e "${VPPDBG_COUNT_MESSAGE}"
    echo "======================================================="
    echo ""
}

check_R4001_createTrack() {
    local R4001_CREATE_TRACK=$(grep -rn 'createTrack returned error' merged_main.log | head -1)

    if [ -z "$R4001_CREATE_TRACK" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "\033[${COLOR}mR4001 VOD 재생안되는 문제\033[0m"
    echo ""
    echo -e "${R4001_CREATE_TRACK}"
    echo "======================================================="
    echo ""   
}

display_hdmi_signal_events() {
    local HPD_EVENTS=$(grep -n 'HPD LOW\|HPD HIGH' dmesg.txt)
    local WAKEUP_SLEEP_EVENTS=$(grep -n 'WakeupServiceImpl: wakeup() called\|STBAPIManager: sleep() called\|STBGlobalkeyBroadCastReceiver.*keyCode : 26.*ACTION_DOWN' merged_main.log)

    if [ -z "$HPD_EVENTS" ] && [ -z "$WAKEUP_SLEEP_EVENTS" ]; then return; fi

    local ALL_EVENTS=$(printf '%s\n%s\n' "$HPD_EVENTS" "$WAKEUP_SLEEP_EVENTS" | grep -v '^$' | sort -t: -k1,1n)

    echo "======================================================="
    echo "STB 입력신호없음 관련 이벤트"
    echo ""

    IFS=$'\n' lines=("${(@f)ALL_EVENTS}")
    for line in "${lines[@]}"; do
        if echo "$line" | grep -q 'HPD LOW\|sleep() called'; then
            COLOR=${COLOR_RED}
        elif echo "$line" | grep -q 'STBGlobalkeyBroadCastReceiver.*keyCode : 26.*ACTION_DOWN'; then
            COLOR="0"
        else
            COLOR=${COLOR_GREEN}
        fi
        echo -e "\033[${COLOR}m${line}\033[0m"
    done

    echo "======================================================="
    echo ""
}

check_hdcp_reauth() {
    local HDCP_REAUTH=$(grep -rn 'hdcptx: hdcptx2: reauth req from ds device' dmesg.txt)

    if [ -z "$HDCP_REAUTH" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "\033[${COLOR}mHDCP2 재인증 요청 감지 (화면 깜박임 원인 가능성)\033[0m"
    echo ""
    echo -e "\033[${COLOR}m${HDCP_REAUTH}\033[0m"
    echo "======================================================="
    echo ""
}

check_invalid_custom() {
    local INVALID_CUSTOM=$(grep -n 'invalid custom' dmesg.txt)

    if [ -z "$INVALID_CUSTOM" ]; then return; fi

    typeset -A CUSTOM_CODE_MAP
    CUSTOM_CODE_MAP=(
        [0xf708bf40]="제조사: TCL / 키: POWER"
        [0x33ccfb04]="제조사: LG / 키: HDMI 2"
        [0x31cefb04]="제조사: LG / 키: HDMI 1"
        [0x3ac5fb04]="제조사: LG / 키: TV OFF"
        [0x3bc4fb04]="제조사: LG / 키: TV ON"
        [0xf708fb04]="제조사: LG / 키: POWER"
    )

    echo "======================================================="
    echo -e "invalid custom 감지"
    echo ""

    IFS=$'\n' lines=("${(@f)INVALID_CUSTOM}")
    for line in "${lines[@]}"; do
        local annotated="$line"
        for code in "${(@k)CUSTOM_CODE_MAP}"; do
            if echo "$line" | grep -q "$code"; then
                annotated="${line} [${CUSTOM_CODE_MAP[$code]}]"
                break
            fi
        done
        echo -e "$annotated"
    done

    echo "======================================================="
    echo ""
}

check_ISET_service_is_null() {
    local ISET_SERVICE_IS_NULL=$(grep -rn 'service is null' merged_main.log)

    if [ -z "$ISET_SERVICE_IS_NULL" ]; then return; fi

    COLOR=${COLOR_RED};
    echo "======================================================="
    echo -e "\033[${COLOR}mBFXBTF-544 버튼동작불가 의심\033[0m"
    echo ""
    echo -e "${ISET_SERVICE_IS_NULL}"
    echo "======================================================="
    echo ""   
}

check_hdmi_status() {
    local cs=$(get_android_property_by_key vendor.skb.hdmi.cs)
    local bit=$(get_android_property_by_key vendor.skb.hdmi.bit)
    local hpd=$(get_android_property_by_key vendor.skb.hdmi.hpd)
    local edid=$(get_android_property_by_key vendor.skb.hdmi.edid)
    local hdcp=$(get_android_property_by_key vendor.skb.hdmi.hdcp)
    local skb_hdcp=$(get_android_property_by_key sys.skb.stb_hdcp)
    local size=$(get_android_property_by_key vendor.skb.hdmi.size)
    echo "======================================================="
    echo "HDMI 관련 Property"
    echo ""
    echo -e "vendor.skb.hdmi.cs\t: $cs"
    echo -e "vendor.skb.hdmi.bit\t: $bit"
    if [ "$hpd" -eq 0 ]; then COLOR=${COLOR_RED}; else COLOR=${COLOR_GREEN}; fi
    echo -e "vendor.skb.hdmi.hpd\t: \033[${COLOR}m"$hpd"\033[0m"
    echo -e "vendor.skb.hdmi.edid\t: $edid"
    if [ "$hdcp" = "HDCP_NONE" ]; then COLOR=${COLOR_RED}; else COLOR=${COLOR_GREEN}; fi
    echo -e "vendor.skb.hdmi.hdcp\t: \033[${COLOR}m"$hdcp"\033[0m"
    echo -e "sys.skb.stb_hdcp\t: $skb_hdcp"
    echo -e "vendor.skb.hdmi.size\t: $size"
    echo "======================================================="
    echo ""
}

ZIP_FILE="$1"

if [[ -n "$ZIP_FILE" && -f "$ZIP_FILE" ]]; then
    WORK_DIR="${ZIP_FILE%.zip}"
    mkdir -p "$WORK_DIR"
    unzip -q "$ZIP_FILE" -d "$WORK_DIR"
    cd "$WORK_DIR"
fi

merged_main_log="merged_main.log"

rm -rf "$merged_main_log"

# Merge main.log files
for i in {4..1}; do
    if [ -f "main.log.$i" ]; then
        cat "main.log.$i" >> "$merged_main_log"
    fi
done

# Merge main.log if exists
if [ -f "main.log" ]; then
    cat "main.log" >> "$merged_main_log"
fi

merged_system_log="merged_system.log"

rm -rf "$merged_system_log"

# Merge system.log files
for i in {4..1}; do
    if [ -f "system.log.$i" ]; then
        cat "system.log.$i" >> "$merged_system_log"
    fi
done

# Merge system.log if exists
if [ -f "system.log" ]; then
    cat "system.log" >> "$merged_system_log"
fi

display_uptime
display_stb_on_property
display_tv_power_control_property
display_tv_information
display_rcu_iset_information
check_hdmi_status
display_hdmi_signal_events
display_rcu_information
display_audio_output_path
display_audio_delay
display_volume_level
display_channel_information
display_front_mic_on_off
display_stb_screen_settings
display_stb_startscreen_settings
display_stb_mac_address

check_video_freezing
check_nugu_broadcast_receiver
check_memtrack_page_allocation_failure
check_pushAmpBD_failed
check_VideoReleaseThread
check_ISET_service_is_null
check_hdcp_reauth

display_keycode_history
check_invalid_custom

open_tombstone_files
