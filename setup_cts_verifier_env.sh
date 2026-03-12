#!/bin/bash

set -u

PACKAGE_NAME="com.android.cts.verifier"
MAIN_ACTIVITY="com.android.cts.verifier/.CtsVerifierActivity"

usage() {
    echo "Usage: $0 <adb_device_serial> <CtsVerifier.apk>"
    echo "Example: $0 GZ2503088N180087 ./CtsVerifier.apk"
    exit 1
}

log() {
    echo "[INFO] $*"
}

warn() {
    echo "[WARN] $*"
}

err() {
    echo "[ERROR] $*" >&2
}

if [ $# -ne 2 ]; then
    usage
fi

DEVICE="$1"
APK_PATH="$2"
ADB=(adb -s "$DEVICE")

run_adb() {
    "${ADB[@]}" "$@"
    return $?
}

device_exists() {
    adb devices | awk 'NR>1 && $2 ~ /device|offline|unauthorized/ {print $1}' | grep -Fxq "$DEVICE"
}

device_ready() {
    adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -Fxq "$DEVICE"
}

get_sdk_version() {
    run_adb shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r'
}

is_package_installed() {
    run_adb shell pm path "$PACKAGE_NAME" 2>/dev/null | grep -q "^package:"
}

apply_step() {
    local desc="$1"
    shift

    log "$desc"
    if run_adb "$@"; then
        echo "  -> OK"
        return 0
    else
        warn "failed: $desc"
        return 1
    fi
}

install_apk() {
    log "Install CTS Verifier APK: $APK_PATH"
    if run_adb install -r -g "$APK_PATH"; then
        echo "  -> OK"
        return 0
    else
        err "APK install failed"
        return 1
    fi
}

launch_cts_verifier() {
    log "Launch CTS Verifier"
    if run_adb shell am start -n "$MAIN_ACTIVITY"; then
        echo "  -> OK"
    else
        warn "failed to launch CTS Verifier with explicit activity"
        log "Try monkey launch fallback"
        if run_adb shell monkey -p "$PACKAGE_NAME" -c android.intent.category.LAUNCHER 1; then
            echo "  -> OK"
        else
            warn "failed to launch CTS Verifier"
        fi
    fi
}

print_summary() {
    echo
    echo "======================================="
    echo " Device            : $DEVICE"
    echo " SDK Version       : $SDK_VERSION"
    echo " Package           : $PACKAGE_NAME"
    echo " APK Path          : $APK_PATH"
    echo "======================================="
}

main() {
    if ! command -v adb >/dev/null 2>&1; then
        err "adb not found"
        exit 1
    fi

    if [ ! -f "$APK_PATH" ]; then
        err "APK file not found: $APK_PATH"
        exit 1
    fi

    if ! device_exists; then
        err "device not found in adb devices: $DEVICE"
        exit 1
    fi

    if ! device_ready; then
        err "device is not in 'device' state. Check authorization/offline status: $DEVICE"
        adb devices
        exit 1
    fi

    if ! run_adb get-state >/dev/null 2>&1; then
        err "adb connection failed: $DEVICE"
        exit 1
    fi

    SDK_VERSION="$(get_sdk_version)"

    if ! [[ "$SDK_VERSION" =~ ^[0-9]+$ ]]; then
        err "failed to read ro.build.version.sdk"
        exit 1
    fi

    print_summary

    echo
    install_apk || exit 1

    echo
    if is_package_installed; then
        log "CTS Verifier is installed"
    else
        err "CTS Verifier package not detected after install"
        exit 1
    fi

    echo
    log "Apply CTS Verifier required settings"

    apply_step "Enable hidden API access" \
        shell settings put global hidden_api_policy 1

    if [ "$SDK_VERSION" -ge 29 ]; then
        apply_step "Grant READ_DEVICE_IDENTIFIERS appop (Android 10+)" \
            shell appops set "$PACKAGE_NAME" android:read_device_identifiers allow
    fi

    if [ "$SDK_VERSION" -ge 30 ]; then
        apply_step "Grant MANAGE_EXTERNAL_STORAGE appop (Android 11+)" \
            shell appops set "$PACKAGE_NAME" MANAGE_EXTERNAL_STORAGE 0
    fi

    if [ "$SDK_VERSION" -ge 33 ]; then
        apply_step "Enable ALLOW_TEST_API_ACCESS compat flag (Android 13+)" \
            shell am compat enable ALLOW_TEST_API_ACCESS "$PACKAGE_NAME"
    fi

    if [ "$SDK_VERSION" -ge 34 ]; then
        apply_step "Grant TURN_SCREEN_ON appop (Android 14+)" \
            shell appops set "$PACKAGE_NAME" TURN_SCREEN_ON 0
    fi

    echo
    log "Apply recommended settings"

    apply_step "Keep screen on while plugged in" \
        shell settings put global stay_on_while_plugged_in 3

    apply_step "Disable screen timeout" \
        shell settings put system screen_off_timeout 2147483647

    apply_step "Wake up screen" \
        shell input keyevent KEYCODE_WAKEUP

    apply_step "Unlock screen with MENU keyevent" \
        shell input keyevent KEYCODE_MENU

    echo
    log "Current device date/time"
    run_adb shell date

    echo
    launch_cts_verifier

    echo
    log "CTS Verifier environment setup completed"
}

main
