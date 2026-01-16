#!/bin/bash
# ============================
# 📦 SCP 파일 추출 스크립트 (ALL 지원 버전)
# ============================

################################
# 모델 선택
################################
echo "=========================================="
echo "📺 모델명을 선택하세요:"
echo "1) BFX-AT100"
echo "2) BFX-UA300"
echo "3) BFX-AT400"
echo "=========================================="
read -p "👉 번호를 입력하세요 (1-3): " MODEL_NUM

case "$MODEL_NUM" in
  1) MODEL="BFX-AT100" ;;
  2) MODEL="BFX-UA300" ;;
  3) MODEL="BFX-AT400" ;;
  *) echo "❌ 잘못된 입력입니다."; exit 1 ;;
esac

echo "✅ 선택된 모델: $MODEL"
echo

################################
# 테스트 선택
################################
echo "=========================================="
echo "🧪 테스트 항목을 선택하세요:"
echo "0) ALL"
echo "1) CTS"
echo "2) CTS-on-GSI"
echo "3) STS"
echo "4) GTS"
echo "5) VTS"
echo "6) TVTS"
echo "=========================================="
read -p "👉 번호를 입력하세요 (0-6): " TEST_NUM

if [ "$TEST_NUM" == "0" ]; then
    TEST_LIST=("CTS" "CTS-on-GSI" "STS" "GTS" "VTS" "TVTS")
    FOLDER_NAME="latest"
    echo "✅ ALL 선택됨 → 모든 테스트 추출"
    echo "📁 폴더 이름: latest"
else
    case "$TEST_NUM" in
      1) TEST_LIST=("CTS") ;;
      2) TEST_LIST=("CTS-on-GSI") ;;
      3) TEST_LIST=("STS") ;;
      4) TEST_LIST=("GTS") ;;
      5) TEST_LIST=("VTS") ;;
      6) TEST_LIST=("TVTS") ;;
      *) echo "❌ 잘못된 입력입니다."; exit 1 ;;
    esac

    read -p "📁 추출하고 싶은 폴더 이름을 입력하세요: " FOLDER_NAME
    if [ -z "$FOLDER_NAME" ]; then
      echo "❌ 폴더 이름은 비워둘 수 없습니다."
      exit 1
    fi
fi

################################
# 테스트별 처리 함수
################################
extract_one_test() {
    local TEST="$1"

    # 테스트별 디렉토리
    case "$TEST" in
        "CTS"|"CTS-on-GSI") TEST_DIR="android-cts" ;;
        "STS")             TEST_DIR="android-sts" ;;
        "GTS")             TEST_DIR="android-gts" ;;
        "VTS")             TEST_DIR="android-vts" ;;
        "TVTS")            TEST_DIR="android-tvts" ;;
        *) echo "❌ 알 수 없는 테스트: $TEST"; return ;;
    esac

    # 원격 IP 자동 설정
    case "$MODEL" in
        "BFX-AT400")
            [ "$TEST" == "CTS" ] && REMOTE_IP="192.168.3.210" || REMOTE_IP="192.168.3.211"
            ;;
        "BFX-AT100")
            [ "$TEST" == "CTS" ] && REMOTE_IP="192.168.2.201" || REMOTE_IP="192.168.2.203"
            ;;
        "BFX-UA300")
            REMOTE_IP="192.168.2.204"
            ;;
    esac

    # USER 매핑
    case "$REMOTE_IP" in
        192.168.3.210) USER="dev2-google10" ;;
        192.168.3.211) USER="dev2-google11" ;;
        192.168.2.201) USER="dev2-google01" ;;
        192.168.2.203) USER="dev2-google03" ;;
        192.168.2.204) USER="dev2-google04" ;;
        *) echo "❌ USER 매핑 실패"; return ;;
    esac

    REMOTE_PATH="/home/${USER}/${TEST_DIR}/latest/${TEST_DIR}/results/${FOLDER_NAME}"
    REMOTE_LOG_PATH="/home/${USER}/${TEST_DIR}/latest/${TEST_DIR}/logs/${FOLDER_NAME}"

    DEST_PATH="$HOME/Downloads/${MODEL}/${TEST}_$(date +"%Y%m%d_%H%M")"
    mkdir -p "$DEST_PATH"

    echo "------------------------------------------"
    echo "🔁 [$TEST] 결과 추출 중..."
    echo "FROM: ${USER}@${REMOTE_IP}:${REMOTE_PATH}"
    echo "TO:   ${DEST_PATH}"
    echo "------------------------------------------"

    scp -r "${USER}@${REMOTE_IP}:${REMOTE_PATH}" "${DEST_PATH}/${FOLDER_NAME}" >/dev/null 2>&1
    scp "${USER}@${REMOTE_IP}:${REMOTE_PATH}.zip" "${DEST_PATH}/${FOLDER_NAME}.zip" >/dev/null 2>&1
    scp -r "${USER}@${REMOTE_IP}:${REMOTE_LOG_PATH}" "${DEST_PATH}/${FOLDER_NAME}_log" >/dev/null 2>&1

    if [ $? -eq 0 ]; then
        zip -r "${DEST_PATH}/${FOLDER_NAME}_log.zip" "${DEST_PATH}/${FOLDER_NAME}_log" >/dev/null 2>&1
        echo "✅ [$TEST] 완료"
    else
        echo "❌ [$TEST] 실패"
    fi
}

################################
# 실행
################################
for T in "${TEST_LIST[@]}"; do
    extract_one_test "$T"
done

echo
echo "🎉 모든 작업 완료!"
