#!/bin/zsh

# 첫 번째 파라미터: 동영상 파일 이름
VIDEO_NAME=$1

# 두 번째 파라미터: 1~12 사이 숫자
NUMBER=$2

# 파라미터 유효성 검사
if [[ -z "$VIDEO_NAME" || -z "$NUMBER" ]]; then
  echo "사용법: $0 <video_name> <1~12>"
  exit 1
fi

if ! [[ "$NUMBER" =~ ^[0-9]+$ ]] || (( NUMBER < 1 || NUMBER > 12 )); then
  echo "에러: 두 번째 파라미터는 1~12 사이의 숫자여야 합니다."
  exit 1
fi

# 확장자 분리
BASENAME="${VIDEO_NAME%.*}"
EXTENSION="${VIDEO_NAME##*.}"

# 출력 파일 이름 생성
OUTPUT_NAME="${BASENAME}_STB#${NUMBER}.${EXTENSION}"

echo "입력 파일:  $VIDEO_NAME"
echo "출력 파일:  $OUTPUT_NAME"
echo "처리 중... (NUMBER=$NUMBER)"

# ffmpeg 명령 분기
case $NUMBER in
  1)  CROP="crop=320:360:0:0" ;;
  2)  CROP="crop=320:360:320:0" ;;
  3)  CROP="crop=320:360:640:0" ;;
  4)  CROP="crop=320:360:960:0" ;;
  5)  CROP="crop=320:360:0:360" ;;
  6)  CROP="crop=320:360:320:360" ;;
  7)  CROP="crop=320:360:640:360" ;;
  8)  CROP="crop=320:360:960:360" ;;
  9)  CROP="crop=640:360:0:0" ;;
  10) CROP="crop=640:360:640:0" ;;
  11) CROP="crop=640:360:0:360" ;;
  12) CROP="crop=640:360:640:360" ;;
esac

# ffmpeg 실행
ffmpeg -i "$VIDEO_NAME" -filter:v "$CROP" -c:a copy "$OUTPUT_NAME"

# 완료 메시지
if [[ $? -eq 0 ]]; then
  echo "✅ 완료: $OUTPUT_NAME 생성됨"
else
  echo "❌ 오류 발생"
fi

