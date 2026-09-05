#!/usr/bin/env bash
set -euo pipefail

# Gradle wrapper script for Android app
# This is a simplified wrapper - in production use official Gradle wrapper

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRADLE_VERSION="8.0"

echo "Parser Template Android App - Build Script"
echo "==========================================="
echo ""

usage() {
    cat <<USAGE
Usage: $0 [command]

Commands:
  build       Build debug APK
  release     Build release APK
  clean       Clean build artifacts
  install     Install debug APK on connected device
  test        Run unit tests
  help        Show this help message

Examples:
  $0 build      # Build debug APK
  $0 release   # Build release APK
  $0 install   # Install on device

Note: This script requires Android SDK and Java to be installed.
For full functionality, use Android Studio or the official Gradle wrapper.
USAGE
}

check_requirements() {
    local missing=0
    
    if ! command -v java &>/dev/null; then
        echo "ERROR: Java is not installed or not in PATH"
        missing=1
    fi
    
    if [[ -z "${ANDROID_HOME:-}" ]] && [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
        echo "WARNING: ANDROID_HOME or ANDROID_SDK_ROOT not set"
        echo "         Some operations may fail"
    fi
    
    return $missing
}

build_debug() {
    echo "Building debug APK..."
    
    if command -v gradle &>/dev/null; then
        gradle assembleDebug
    elif [[ -f "$SCRIPT_DIR/gradlew" ]]; then
        "$SCRIPT_DIR/gradlew" assembleDebug
    else
        echo "ERROR: Gradle not found. Please install Gradle or use Android Studio."
        return 1
    fi
    
    echo ""
    echo "Build complete. APK location:"
    find "$SCRIPT_DIR/app/build/outputs/apk" -name "*-debug.apk" 2>/dev/null || echo "  (not found)"
}

build_release() {
    echo "Building release APK..."
    
    if command -v gradle &>/dev/null; then
        gradle assembleRelease
    elif [[ -f "$SCRIPT_DIR/gradlew" ]]; then
        "$SCRIPT_DIR/gradlew" assembleRelease
    else
        echo "ERROR: Gradle not found. Please install Gradle or use Android Studio."
        return 1
    fi
    
    echo ""
    echo "Build complete. APK location:"
    find "$SCRIPT_DIR/app/build/outputs/apk" -name "*-release.apk" 2>/dev/null || echo "  (not found)"
}

clean_build() {
    echo "Cleaning build artifacts..."
    
    if command -v gradle &>/dev/null; then
        gradle clean
    elif [[ -f "$SCRIPT_DIR/gradlew" ]]; then
        "$SCRIPT_DIR/gradlew" clean
    else
        rm -rf "$SCRIPT_DIR/app/build"
        rm -rf "$SCRIPT_DIR/build"
        echo "Cleaned build directories"
    fi
}

install_app() {
    echo "Installing app on connected device..."
    
    if ! command -v adb &>/dev/null; then
        echo "ERROR: adb not found. Please install Android SDK Platform Tools."
        return 1
    fi
    
    local apk_path
    apk_path=$(find "$SCRIPT_DIR/app/build/outputs/apk" -name "*-debug.apk" 2>/dev/null | head -1)
    
    if [[ -z "$apk_path" ]]; then
        echo "No debug APK found. Building first..."
        build_debug
        apk_path=$(find "$SCRIPT_DIR/app/build/outputs/apk" -name "*-debug.apk" 2>/dev/null | head -1)
    fi
    
    if [[ -n "$apk_path" ]]; then
        adb install -r "$apk_path"
        echo "Installation complete"
    else
        echo "ERROR: Could not find APK file"
        return 1
    fi
}

run_tests() {
    echo "Running unit tests..."
    
    if command -v gradle &>/dev/null; then
        gradle test
    elif [[ -f "$SCRIPT_DIR/gradlew" ]]; then
        "$SCRIPT_DIR/gradlew" test
    else
        echo "ERROR: Gradle not found"
        return 1
    fi
}

# Main
if [[ $# -eq 0 ]]; then
    usage
    exit 0
fi

case "$1" in
    build)
        check_requirements || exit 1
        build_debug
        ;;
    release)
        check_requirements || exit 1
        build_release
        ;;
    clean)
        clean_build
        ;;
    install)
        check_requirements || exit 1
        install_app
        ;;
    test)
        check_requirements || exit 1
        run_tests
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        echo "Unknown command: $1"
        usage
        exit 64
        ;;
esac
