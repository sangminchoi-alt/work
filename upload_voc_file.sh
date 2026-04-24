#!/bin/zsh

FTP_SERVER="altserver01.iptime.org"
HTTP_SERVER="http://altserver01.iptime.org"
FTP_USER="alt"
FTP_PASSWORD="alt1234"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <file>"
    exit 1
fi

FILE_PATH="$1"

if [[ ! -f "$FILE_PATH" ]]; then
    echo "Error: file not found -> $FILE_PATH"
    exit 1
fi

FILE_NAME=$(basename "$FILE_PATH")
TODAY=$(date +%Y%m%d)
REMOTE_DIR="/smart4/voc/${TODAY}"

echo "Uploading $FILE_NAME ..."

curl -sS -T "$FILE_PATH" \
     -u "${FTP_USER}:${FTP_PASSWORD}" \
     "ftp://${FTP_SERVER}${REMOTE_DIR}/${FILE_NAME}" \
     --ftp-create-dirs \
     > /dev/null

if [[ $? -ne 0 ]]; then
    echo "Upload failed"
    exit 1
fi

~/Downloads/work/voc_analysis.sh ${FILE_PATH}

rm -rf ${FILE_PATH}

DOWNLOAD_URL="${HTTP_SERVER}${REMOTE_DIR}/${FILE_NAME}"

# 클립보드 복사
if command -v pbcopy >/dev/null 2>&1; then
    printf "%s" "$DOWNLOAD_URL" | pbcopy
    CLIP_MSG="(copied to clipboard)"
elif command -v xclip >/dev/null 2>&1; then
    printf "%s" "$DOWNLOAD_URL" | xclip -selection clipboard
    CLIP_MSG="(copied to clipboard)"
elif command -v xsel >/dev/null 2>&1; then
    printf "%s" "$DOWNLOAD_URL" | xsel --clipboard --input
    CLIP_MSG="(copied to clipboard)"
else
    CLIP_MSG="(clipboard copy not supported)"
fi

echo ""
echo "Upload complete"
echo "$DOWNLOAD_URL"
echo "$CLIP_MSG"
