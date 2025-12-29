#!/bin/bash

set -e

if [ $# -ne 2 ]; then
    echo "Usage: $0 <adb_serial> <ota_archive_file>"
    exit 1
fi

ADB_SERIAL="$1"
OTA_ARCHIVE="$2"

WORKDIR="$(pwd)/ota_work"
UNZIPDIR="$WORKDIR/usb_bfx-at400"
UPDATE_DIR="$UNZIPDIR/update"

ADB="adb -s ${ADB_SERIAL}"

echo "[0] Check device connection"
$ADB get-state >/dev/null

echo "[1] adb root"
$ADB root
sleep 2
$ADB wait-for-device

echo "[2] Clean workspace"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"

echo "[3] Extract OTA archive"
case "$OTA_ARCHIVE" in
    *.zip)
        unzip -q "$OTA_ARCHIVE" -d "$WORKDIR"
        ;;
    *.tar.gz|*.tgz)
        tar -xzf "$OTA_ARCHIVE" -C "$WORKDIR"
        ;;
    *)
        echo "Unsupported archive format"
        exit 1
        ;;
esac

if [ ! -f "$UNZIPDIR/update.zip" ]; then
    echo "update.zip not found after extraction"
    exit 1
fi

echo "[4] Extract update.zip"
mkdir -p "$UPDATE_DIR"
unzip -q "$UNZIPDIR/update.zip" -d "$UPDATE_DIR"

META_FILE="$UPDATE_DIR/META-INF/com/android/metadata"
PROP_FILE="$UPDATE_DIR/payload_properties.txt"

if [ ! -f "$META_FILE" ] || [ ! -f "$PROP_FILE" ]; then
    echo "Required files not found"
    exit 1
fi

echo "[5] Parse payload offset & size"

LINE=$(grep ota-streaming-property-files "$META_FILE")

# payload.bin:OFFSET:SIZE
read OFFSET SIZE <<< $(echo "$LINE" | \
    sed -E 's/.*payload.bin:([0-9]+):([0-9]+).*/\1 \2/')

echo "  OFFSET=$OFFSET"
echo "  SIZE=$SIZE"

echo "[6] Read payload headers"
HEADERS=$(cat "$PROP_FILE")

echo "[7] Push update.zip to device (/cache)"
$ADB push "$UNZIPDIR/update.zip" /cache/update.zip

echo "[8] Run update_engine_client"

$ADB shell <<EOF
update_engine_client \
  --update \
  --follow \
  --payload=file:///cache/update.zip \
  --offset=${OFFSET} \
  --size=${SIZE} \
  --headers="${HEADERS}"
EOF

echo "Done."
