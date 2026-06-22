#!/bin/bash

# 모델명, 펌웨어버전 가져오기
MODEL=$(adb shell getprop ro.build.product | tr -d '\r')
VERSION=$(adb shell cat /btv_home/config/version.txt | tr -d '\r\n')
TIMESTAMP=$(date +"%Y%m%d_%H%M")

FILENAME="logcat_${MODEL}_${VERSION}_${TIMESTAMP}.txt"

echo "저장 파일명: $FILENAME"

# 기존 logcat 버퍼 클리어 후 캡처 시작
adb logcat -c
adb logcat > "$FILENAME"
