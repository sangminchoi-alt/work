#!/bin/bash
# ============================
# 📦 SCP 파일 추출 스크립트 (최종 버전)
# ============================

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

# --- 테스트 항목 선택 ---
echo "=========================================="
echo "🧪 테스트 항목을 선택하세요:"
echo "1) CTS"
echo "2) CTS-on-GSI"
echo "3) STS"
echo "4) GTS"
echo "5) VTS"
echo "6) TVTS"
echo "=========================================="
read -p "👉 번호를 입력하세요 (1-6): " TEST_NUM

case "$TEST_NUM" in
  1) TEST="CTS" ;;
  2) TEST="CTS-on-GSI" ;;
  3) TEST="STS" ;;
  4) TEST="GTS" ;;
  5) TEST="VTS" ;;
  6) TEST="TVTS" ;;
  *) echo "❌ 잘못된 입력입니다."; exit 1 ;;
esac

echo "✅ 선택된 테스트: $TEST"
echo

# --- 폴더 이름 입력 ---
read -p "📁 추출하고 싶은 폴더 이름을 입력하세요: " FOLDER_NAME
if [ -z "$FOLDER_NAME" ]; then
  echo "❌ 폴더 이름은 비워둘 수 없습니다."
  exit 1
fi

echo "✅ 입력된 폴더 이름: $FOLDER_NAME"
echo

# --- 원격 IP 자동 설정 ---
if [ "$MODEL" == "BFX-AT400" ]; then
    if [ "$TEST" == "CTS" ]; then
        REMOTE_IP="192.168.2.210"
    else
        REMOTE_IP="192.168.2.211"
    fi
    echo "🌐 자동 설정된 원격 IP: $REMOTE_IP"
elif [ "$MODEL" == "BFX-AT100" ]; then
    if [ "$TEST" == "CTS" ]; then
        REMOTE_IP="192.168.2.201"
    else
        REMOTE_IP="192.168.2.203"
    fi
    echo "🌐 자동 설정된 원격 IP: $REMOTE_IP"
elif [ "$MODEL" == "BFX-UA300" ]; then
    if [ "$TEST" == "CTS" ]; then
        REMOTE_IP="192.168.2.205"
    else
        REMOTE_IP="192.168.2.204"
    fi
    echo "🌐 자동 설정된 원격 IP: $REMOTE_IP"
else
    read -p "🌐 원격 IP 주소: " REMOTE_IP
fi

  # 테스트별 디렉토리 매핑
  case "$TEST" in
      "CTS")        TEST_DIR="android-cts" ;;
      "CTS-on-GSI") TEST_DIR="android-cts" ;;
      "STS")        TEST_DIR="android-sts" ;;
      "GTS")        TEST_DIR="android-gts" ;;
      "VTS")        TEST_DIR="android-vts" ;;
      "TVTS")       TEST_DIR="android-tvts" ;;
      *) echo "❌ 지원하지 않는 테스트명"; exit 1 ;;
  esac

# --- USER 및 REMOTE_PATH 자동 설정 ---
if [ "$REMOTE_IP" == "192.168.2.210" ]; then
    USER="dev2-google10"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.211" ]; then
    USER="dev2-google11"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.201" ]; then
    USER="dev2-google01"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.202" ]; then
    USER="dev2-google02"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.203" ]; then
    USER="dev2-google03"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.204" ]; then
    USER="dev2-google04"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
elif [ "$REMOTE_IP" == "192.168.2.205" ]; then
    USER="dev2-google-05"

    echo "👤 USER 자동 설정됨: $USER"
    echo "📂 REMOTE_PATH 자동 설정됨: $REMOTE_PATH"
else
    echo "❌ REMOTE_IP 가 맞지 않습니다."
    exit
fi

REMOTE_PATH="/home/${USER}/${TEST_DIR}/latest/${TEST_DIR}/results/${FOLDER_NAME}"
REMOTE_LOG_PATH="/home/${USER}/${TEST_DIR}/latest/${TEST_DIR}/logs/${FOLDER_NAME}"

# --- SCP 실행 ---
DEST_PATH="/Users/tonight0210/Downloads/${MODEL}/${TEST}_$(date +"%Y%m%d_%H%M")"

echo "------------------------------------------"
echo "🔁 파일 복사 중..."
echo "USER:   ${USER}"
echo "FROM:   ${USER}@${REMOTE_IP}:${REMOTE_PATH}"
echo "TO:     ${DEST_PATH}/"
echo "------------------------------------------"

mkdir -p "${DEST_PATH}"
scp -r "${USER}@${REMOTE_IP}:${REMOTE_PATH}" "${DEST_PATH}/${FOLDER_NAME}" >/dev/null 2>&1
scp "${USER}@${REMOTE_IP}:${REMOTE_PATH}.zip" "${DEST_PATH}/${FOLDER_NAME}.zip" >/dev/null 2>&1

scp -r "${USER}@${REMOTE_IP}:${REMOTE_LOG_PATH}" "${DEST_PATH}/${FOLDER_NAME}_log" >/dev/null 2>&1

# 로그 폴더 압축
if [ $? -eq 0 ]; then
    echo "🗜  로그 폴더 압축 중..."
    zip -r "${DEST_PATH}/${FOLDER_NAME}_log.zip" "${DEST_PATH}/${FOLDER_NAME}_log" >/dev/null 2>&1
    echo "📦 압축 완료: ${DEST_PATH}/${FOLDER_NAME}_log.zip"
else
    echo "❌ 로그 폴더 다운로드 중 오류 발생!"
fi

if [ $? -eq 0 ]; then
    echo "✅ 완료! ${DEST_PATH}/ 에 파일이 복사되었습니다."
else
    echo "❌ SCP 복사 중 오류 발생!"
fi
