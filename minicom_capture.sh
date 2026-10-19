#!/bin/bash
# minicom 실행과 동시에 시리얼 로그를 파일로 저장
# 사용법: ./minicom_capture.sh [device] [baudrate] [log_dir]

DEVICE="${1:-/dev/tty.usbmodem5A460359091}"
BAUDRATE="${2:-115200}"
LOG_DIR="${3:-$HOME/Downloads/work/serial_logs}"

if [ ! -e "$DEVICE" ]; then
    echo "Device not found: $DEVICE"
    ls /dev/tty.usb* 2>/dev/null
    exit 1
fi

mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="$LOG_DIR/minicom_${TIMESTAMP}.txt"

echo "[$(date)] Device: $DEVICE ($BAUDRATE), Log: $LOG_FILE"

# -C: 캡처 파일 저장, -w: 줄바꿈 활성화, -c on: 컬러
minicom -D "$DEVICE" -b "$BAUDRATE" -C "$LOG_FILE" -w -c on

echo "[$(date)] Saved $LOG_FILE"
