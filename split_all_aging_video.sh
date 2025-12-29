#!/bin/zsh

# 첫 번째 파라미터: 동영상 파일 이름
VIDEO_NAME=$1

# 파라미터 유효성 검사
if [[ -z "$VIDEO_NAME" ]]; then
  echo "사용법: $0 <video_name>"
  exit 1
fi

if [[ ! -f "$VIDEO_NAME" ]]; then
  echo "에러: 파일이 존재하지 않습니다 -> $VIDEO_NAME"
  exit 1
fi

# ffprobe를 사용해 해상도 추출 (ffmpeg 설치 필요)
RESOLUTION=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height \
  -of csv=p=0:s=x "$VIDEO_NAME" 2>/dev/null)

if [[ -z "$RESOLUTION" ]]; then
  echo "에러: 해상도를 가져올 수 없습니다. (ffprobe 확인 필요)"
  exit 1
fi

echo "동영상 이름: $VIDEO_NAME"
echo "해상도: $RESOLUTION"

# 해상도에 따라 NUMBER 결정
case "$RESOLUTION" in
  "1920x1080")
    NUMBER=1
    START=1
    END=8
    ;;
  "1280x720")
    NUMBER=2
    START=9
    END=12
    ;;
  *)
    echo "에러: 지원하지 않는 해상도 ($RESOLUTION)"
    echo "지원 해상도: 1920x1080 또는 1280x720"
    exit 1
    ;;
esac

echo "결정된 그룹 번호: $NUMBER"

# 반복 실행
for (( i=$START; i<=$END; i++ )); do
  echo "▶️ 실행 중: ./split_aging_video.sh $VIDEO_NAME $i"
  ./split_aging_video.sh "$VIDEO_NAME" "$i"
  if [[ $? -ne 0 ]]; then
    echo "❌ split_aging_video.sh 실행 실패 (번호: $i)"
    exit 1
  fi
done

echo "✅ 모든 작업 완료"

