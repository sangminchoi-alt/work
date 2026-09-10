#!/bin/bash
#
# 서버의 펌웨어 zip을 받아 adb로 기기에 업그레이드하는 스크립트
#
# 동작:
#   1. 펌웨어 zip을 받아온다.
#      - 로컬에 존재하는 파일(상대/절대경로)이 주어지면 다운로드 없이 그 파일을 그대로 사용
#      - http/https/ftp 주소가 주어지면 wget으로 다운로드 (계정: alt / alt1234)
#      - 로컬에 없는 절대경로(예: /home/smchoi/.../usb_bfx-ua300_V19.561.103_SD.zip)가 주어지면
#        scp로 원격 빌드 서버에서 다운로드 (모델별 접속정보는 아래 SCP_MODELS/SCP_HOSTS/SCP_PORTS 참고)
#   2. 압축 해제 -> 안의 최상위 폴더명(모델별로 다름, 예: usb_bfx-at400)을 자동 인식
#   3. adb 장치 목록을 보여주고 키보드로 업그레이드할 장치 선택
#      - "새로운 장치 연결": IP 입력 -> adb connect -> 장치 선택 메뉴로 복귀
#      - "업그레이드하지 않고 종료": 종료
#      - 연결된 장치가 하나도 없으면 바로 IP 입력을 받고 connect 후 장치 선택 메뉴로 이동
#   4. 선택한 장치에 adb root / push / recovery command 설정 / reboot recovery 수행
#
# 사용법:
#   ./upgrade_firmware.sh <로컬 파일 | 다운로드주소 | 원격 서버의 절대경로>
#
# 예시:
#   ./upgrade_firmware.sh usb_bfx-at400_V24.551.612_SD.zip
#   ./upgrade_firmware.sh ~/Downloads/usb_bfx-at400_V24.551.612_SD.zip
#   ./upgrade_firmware.sh http://altserver01.iptime.org/build_bot/BFX-AT400/OS14/.../SD/usb_bfx-at400_V24.561.130_SD.zip
#   ./upgrade_firmware.sh /home/smchoi/project/BFX-UA300_OS10/Release/BFX-UA300_20260804_SD_561r103/usb_bfx-ua300_V19.561.103_SD.zip
#
set -uo pipefail

FTP_USER="alt"
FTP_PASS="alt1234"

# 절대경로로 지정된 펌웨어를 scp로 받아올 때 모델별 접속정보.
# 경로에 모델명(대소문자 무관)이 포함되어 있으면 매칭된다. (같은 인덱스끼리 대응, bash 3 호환을 위해 배열로 관리)
SCP_MODELS=(BFX-UA300 BFX-AT100 BFX-AT400)
SCP_HOSTS=(smchoi@altserver01.iptime.org smchoi@altserver01.iptime.org smchoi@192.168.2.106)
SCP_PORTS=(803 803 "")

usage() {
    echo "사용법: $(basename "$0") <로컬 파일 | 다운로드주소 | 원격 서버의 절대경로>" >&2
    echo "예:     $(basename "$0") usb_bfx-at400_V24.551.612_SD.zip" >&2
    echo "        $(basename "$0") http://altserver01.iptime.org/.../usb_bfx-at400_V24.561.130_SD.zip" >&2
    echo "        $(basename "$0") /home/smchoi/project/BFX-UA300_OS10/Release/.../usb_bfx-ua300_V19.561.103_SD.zip" >&2
    exit 1
}

[ $# -eq 1 ] || usage
FTP_URL="$1"

SOURCE_MODE="wget"
SCP_HOST=""
SCP_PORT=""
LOCAL_ZIP=""

# 로컬에 실제로 존재하는 파일이면 다운로드하지 않고 그대로 사용한다.
if [ -f "$FTP_URL" ]; then
    SOURCE_MODE="local"
    LOCAL_ZIP="$(cd "$(dirname "$FTP_URL")" && pwd)/$(basename "$FTP_URL")"
    if [ ! -r "$LOCAL_ZIP" ]; then
        echo "에러: 파일을 읽을 수 없습니다: ${LOCAL_ZIP}" >&2
        exit 1
    fi
else
    case "$FTP_URL" in
        /*)
            SOURCE_MODE="scp"
            SRC_UPPER="$(echo "$FTP_URL" | tr '[:lower:]' '[:upper:]')"
            for i in "${!SCP_MODELS[@]}"; do
                model_upper="$(echo "${SCP_MODELS[$i]}" | tr '[:lower:]' '[:upper:]')"
                case "$SRC_UPPER" in
                    *"$model_upper"*)
                        SCP_HOST="${SCP_HOSTS[$i]}"
                        SCP_PORT="${SCP_PORTS[$i]}"
                        break
                        ;;
                esac
            done
            if [ -z "$SCP_HOST" ]; then
                echo "에러: 경로에서 모델을 인식할 수 없어 scp 접속정보를 찾을 수 없습니다: ${FTP_URL}" >&2
                exit 1
            fi
            ;;
        ftp://*|http://*|https://*) ;;
        ./*|../*|~/*)
            echo "에러: 로컬 파일을 찾을 수 없습니다: ${FTP_URL}" >&2
            exit 1
            ;;
        */*) FTP_URL="ftp://${FTP_URL}" ;;
        *)
            # 슬래시가 없는 이름은 로컬 파일을 의도한 것으로 보는 편이 자연스럽다.
            echo "에러: 로컬 파일을 찾을 수 없습니다: ${FTP_URL}" >&2
            echo "      (URL이나 원격 서버의 절대경로를 지정하려면 http://... 또는 /... 형태로 입력하세요)" >&2
            exit 1
            ;;
    esac
fi

REQUIRED_BINS=(unzip adb)
case "$SOURCE_MODE" in
    scp)   REQUIRED_BINS+=(scp) ;;
    wget)  REQUIRED_BINS+=(wget) ;;
    local) ;;
esac

for bin in "${REQUIRED_BINS[@]}"; do
    command -v "$bin" >/dev/null 2>&1 || { echo "에러: '${bin}' 명령을 찾을 수 없습니다." >&2; exit 1; }
done

WORK_DIR="$(mktemp -d /tmp/firmware_upgrade.XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIRMWARE_ZIP="${WORK_DIR}/firmware.zip"
EXTRACT_DIR="${WORK_DIR}/extract"
mkdir -p "$EXTRACT_DIR"

if [ "$SOURCE_MODE" = "local" ]; then
    FIRMWARE_ZIP="$LOCAL_ZIP"
    echo "==> 로컬 파일 사용: ${FIRMWARE_ZIP}"
elif [ "$SOURCE_MODE" = "scp" ]; then
    echo "==> 다운로드: ${FTP_URL}"
    if [ -n "$SCP_PORT" ]; then
        echo "==> scp -P ${SCP_PORT} ${SCP_HOST}:${FTP_URL}"
        SCP_OK=1; scp -P "$SCP_PORT" "${SCP_HOST}:${FTP_URL}" "$FIRMWARE_ZIP" || SCP_OK=0
    else
        echo "==> scp ${SCP_HOST}:${FTP_URL}"
        SCP_OK=1; scp "${SCP_HOST}:${FTP_URL}" "$FIRMWARE_ZIP" || SCP_OK=0
    fi
    if [ "$SCP_OK" -eq 0 ]; then
        echo "에러: 다운로드에 실패했습니다: ${FTP_URL}" >&2
        exit 1
    fi
else
    echo "==> 다운로드: ${FTP_URL}"
    if ! wget --progress=bar:force:noscroll --user="${FTP_USER}" --password="${FTP_PASS}" "$FTP_URL" -O "$FIRMWARE_ZIP"; then
        echo "에러: 다운로드에 실패했습니다: ${FTP_URL}" >&2
        exit 1
    fi
fi

echo "==> 압축 해제: ${FIRMWARE_ZIP}"
if ! unzip -q -o "$FIRMWARE_ZIP" -d "$EXTRACT_DIR"; then
    echo "에러: 압축 해제에 실패했습니다." >&2
    exit 1
fi

# 압축을 풀면 나오는 최상위 폴더명은 모델마다 다르므로 자동으로 찾는다 (예: usb_bfx-at400)
MODEL_DIR=""
while IFS= read -r d; do
    MODEL_DIR="$(basename "$d")"
    break
done < <(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d)

if [ -z "$MODEL_DIR" ]; then
    echo "에러: 압축 해제 후 모델 폴더를 찾을 수 없습니다." >&2
    exit 1
fi

UPDATE_ZIP="${EXTRACT_DIR}/${MODEL_DIR}/update.zip"
if [ ! -f "$UPDATE_ZIP" ]; then
    echo "에러: update.zip 파일을 찾을 수 없습니다: ${UPDATE_ZIP}" >&2
    exit 1
fi

echo "==> 모델 폴더 확인: ${MODEL_DIR}"

# update.zip 안의 META-INF/com/android/metadata에 있는 pre-device 값이 이 펌웨어의 대상 모델명이다.
# 예) pre-device=BFX-AT400
PRE_DEVICE="$(unzip -p "$UPDATE_ZIP" META-INF/com/android/metadata 2>/dev/null | grep '^pre-device=' | head -n1 | cut -d'=' -f2- | tr -d '\r\n')"

if [ -n "$PRE_DEVICE" ]; then
    echo "==> 이 펌웨어의 대상 모델(pre-device): ${PRE_DEVICE}"
else
    echo "경고: update.zip metadata에서 대상 모델(pre-device)을 확인하지 못했습니다. 모델 일치 여부를 검사하지 않습니다." >&2
fi

# post-build-incremental 값(예: 24.561.130-20260701)에서 날짜 부분을 뺀 앞쪽이 펌웨어 버전(ro.vendor.fw.version과 동일한 형식)이다.
TARGET_FW_VERSION="$(unzip -p "$UPDATE_ZIP" META-INF/com/android/metadata 2>/dev/null | grep '^post-build-incremental=' | head -n1 | cut -d'=' -f2- | tr -d '\r\n')"
TARGET_FW_VERSION="${TARGET_FW_VERSION%%-*}"

if [ -n "$TARGET_FW_VERSION" ]; then
    echo "==> 이 펌웨어의 버전: ${TARGET_FW_VERSION}"
else
    echo "경고: update.zip metadata에서 펌웨어 버전(post-build-incremental)을 확인하지 못했습니다." >&2
fi

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

run_upgrade() {
    local serial="$1"

    echo "==> 대상 장치: ${serial}"
    echo "==> adb root"
    adb -s "$serial" root
    adb -s "$serial" wait-for-device

    echo "==> adb push: ${UPDATE_ZIP} -> /cache/update.zip"
    adb -s "$serial" push "$UPDATE_ZIP" /cache/update.zip

    echo "==> recovery command 설정"
    adb -s "$serial" shell 'echo "--update_package=/cache/update.zip" > /cache/recovery/command'
    adb -s "$serial" shell sync

    echo "==> adb reboot recovery"
    adb -s "$serial" reboot recovery

    echo "완료: ${serial} 장치가 recovery 모드로 재부팅되어 업그레이드를 진행합니다."
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

# adb 장치의 ro.product.model 값을 읽는다.
get_device_model() {
    local serial="$1"
    adb -s "$serial" shell getprop ro.product.model 2>/dev/null | tr -d '\r\n'
}

# adb 장치의 현재 펌웨어 버전(ro.vendor.fw.version) 값을 읽는다.
get_device_fw_version() {
    local serial="$1"
    adb -s "$serial" shell getprop ro.vendor.fw.version 2>/dev/null | tr -d '\r\n'
}

to_upper() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

model_matches() {
    [ "$(to_upper "$1")" = "$(to_upper "$2")" ]
}

select_and_upgrade() {
    while true; do
        local devices=()
        while IFS=$'\t' read -r serial state; do
            [ -n "$serial" ] && [ "$state" = "device" ] && devices+=("$serial")
        done < <(adb devices | tail -n +2)

        if [ ${#devices[@]} -eq 0 ]; then
            echo ""
            echo "연결된 adb 장치가 없습니다."
            prompt_connect_new_device
            continue
        fi

        echo ""
        echo "모델명 확인 중..."
        local models=()
        local labels=()
        for serial in "${devices[@]}"; do
            local model fw_version version_part label mismatch
            model="$(get_device_model "$serial")"
            fw_version="$(get_device_fw_version "$serial")"
            models+=("$model")

            mismatch=0
            [ -n "$model" ] && [ -n "$PRE_DEVICE" ] && ! model_matches "$model" "$PRE_DEVICE" && mismatch=1

            if [ "$mismatch" -eq 1 ]; then
                version_part=""
            elif [ -n "$TARGET_FW_VERSION" ]; then
                version_part=" (${fw_version:-?} -> ${TARGET_FW_VERSION})"
            elif [ -n "$fw_version" ]; then
                version_part=" (${fw_version})"
            else
                version_part=""
            fi

            if [ -z "$model" ]; then
                labels+=("$serial")
            else
                label="(${model})${version_part} ${serial}"
                if [ "$mismatch" -eq 1 ]; then
                    label="${label}  [모델 불일치: ${PRE_DEVICE} 전용 펌웨어]"
                fi
                labels+=("$label")
            fi
        done

        echo ""
        echo "연결된 adb 장치 목록: (↑/↓ 이동, Enter 선택)"
        local options=("${labels[@]}" "새로운 장치 연결" "업그레이드하지 않고 종료")
        arrow_menu
        local idx="$ARROW_MENU_INDEX"
        echo ""

        if [ "$idx" -lt "${#devices[@]}" ]; then
            local model="${models[$idx]}"
            if [ -n "$PRE_DEVICE" ] && [ -n "$model" ] && ! model_matches "$model" "$PRE_DEVICE"; then
                echo "에러: 이 펌웨어는 '${PRE_DEVICE}' 전용입니다. 선택한 장치의 모델은 '${model}' 이라 업그레이드를 진행하지 않습니다." >&2
                continue
            fi
            run_upgrade "${devices[$idx]}"
            return
        elif [ "$idx" -eq "${#devices[@]}" ]; then
            prompt_connect_new_device
        else
            echo "업그레이드를 취소합니다."
            exit 0
        fi
    done
}

select_and_upgrade
