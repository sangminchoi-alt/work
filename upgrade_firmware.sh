#!/bin/bash
#
# 서버의 펌웨어 zip을 받아 adb로 기기에 업그레이드하는 스크립트
#
# 동작:
#   1. 주어진 주소(http/https/ftp)에서 wget으로 펌웨어 zip 다운로드 (계정: alt / alt1234)
#   2. 압축 해제 -> 안의 최상위 폴더명(모델별로 다름, 예: usb_bfx-at400)을 자동 인식
#   3. adb 장치 목록을 보여주고 키보드로 업그레이드할 장치 선택
#      - "새로운 장치 연결": IP 입력 -> adb connect -> 장치 선택 메뉴로 복귀
#      - "업그레이드하지 않고 종료": 종료
#      - 연결된 장치가 하나도 없으면 바로 IP 입력을 받고 connect 후 장치 선택 메뉴로 이동
#   4. 선택한 장치에 adb root / push / recovery command 설정 / reboot recovery 수행
#
# 사용법:
#   ./upgrade_firmware.sh <다운로드주소>
#
# 예시:
#   ./upgrade_firmware.sh http://altserver01.iptime.org/build_bot/BFX-AT400/OS14/.../SD/usb_bfx-at400_V24.561.130_SD.zip
#
set -uo pipefail

FTP_USER="alt"
FTP_PASS="alt1234"

usage() {
    echo "사용법: $(basename "$0") <다운로드주소>" >&2
    echo "예:     $(basename "$0") http://altserver01.iptime.org/.../usb_bfx-at400_V24.561.130_SD.zip" >&2
    exit 1
}

[ $# -eq 1 ] || usage
FTP_URL="$1"

case "$FTP_URL" in
    ftp://*|http://*|https://*) ;;
    *) FTP_URL="ftp://${FTP_URL}" ;;
esac

for bin in wget unzip adb; do
    command -v "$bin" >/dev/null 2>&1 || { echo "에러: '${bin}' 명령을 찾을 수 없습니다." >&2; exit 1; }
done

WORK_DIR="$(mktemp -d /tmp/firmware_upgrade.XXXXXX)"
cleanup() { rm -rf "$WORK_DIR"; }
trap cleanup EXIT

FIRMWARE_ZIP="${WORK_DIR}/firmware.zip"
EXTRACT_DIR="${WORK_DIR}/extract"
mkdir -p "$EXTRACT_DIR"

echo "==> 다운로드: ${FTP_URL}"
if ! wget --progress=bar:force:noscroll --user="${FTP_USER}" --password="${FTP_PASS}" "$FTP_URL" -O "$FIRMWARE_ZIP"; then
    echo "에러: 다운로드에 실패했습니다: ${FTP_URL}" >&2
    exit 1
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

    echo "==> adb reboot recovery"
    adb -s "$serial" reboot recovery

    echo "완료: ${serial} 장치가 recovery 모드로 재부팅되어 업그레이드를 진행합니다."
}

# 화살표(↑/↓) + Enter로 고르는 메뉴.
# 호출하는 쪽에서 local 배열 `options`를 준비해두면 되고,
# 결과는 ARROW_MENU_RESULT 변수에 담긴다.
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
        echo "연결된 adb 장치 목록: (↑/↓ 이동, Enter 선택)"
        local options=("${devices[@]}" "새로운 장치 연결" "업그레이드하지 않고 종료")
        arrow_menu
        local opt="$ARROW_MENU_RESULT"
        echo ""

        case "$opt" in
            "새로운 장치 연결")
                prompt_connect_new_device
                ;;
            "업그레이드하지 않고 종료")
                echo "업그레이드를 취소합니다."
                exit 0
                ;;
            *)
                run_upgrade "$opt"
                return
                ;;
        esac
    done
}

select_and_upgrade
