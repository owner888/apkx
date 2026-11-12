#!/usr/bin/env bash
# ============================================================================
# apkx — Core Utilities, Environment & Tool Resolution
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

APKX_VERSION="1.0.0"

# ── ANSI Colors ──────────────────────────────────────────────────────────────
if [ -t 1 ]; then
    RED=$'\033[0;31m'
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    BLUE=$'\033[0;34m'
    CYAN=$'\033[0;36m'
    MAGENTA=$'\033[0;35m'
    BOLD=$'\033[1m'
    DIM=$'\033[2m'
    NC=$'\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    DIM=''
    NC=''
fi

# ── Logging Helpers ──────────────────────────────────────────────────────────
info()  { echo -e "${BLUE}▸${NC} $*"; }
ok()    { echo -e "${GREEN}✔${NC} $*"; }
warn()  { echo -e "${YELLOW}⚠${NC} $*"; }
fail()  { echo -e "${RED}✖${NC} $*" >&2; exit 1; }
step()  { echo -e "\n${MAGENTA}━━━ $* ━━━${NC}"; }

# Legacy log() compatibility: log I|S|W|E "message"
log() {
    local level="$1"
    shift
    case "$level" in
        I) info "$*" ;;
        S) ok "$*"; echo "" ;;
        W) warn "$*" ;;
        E) echo -e "${RED}✖ $*${NC}" >&2 ;;
        *) echo -e "$level $*" ;;
    esac
}

# ── Cross-Platform Helpers (macOS BSD + Linux GNU) ───────────────────────────
sed_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        /usr/bin/sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

sed_regex_inplace() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        /usr/bin/sed -i '' -E "$@"
    else
        sed -i -r "$@"
    fi
}

# ── Directory & Config Resolution ────────────────────────────────────────────
APKX_HOME="${APKX_HOME:-$APKX_ROOT_DIR}"
APKX_BIN_DIR="${APKX_BIN_DIR:-$APKX_ROOT_DIR/bin}"

find_jar() {
    local pattern="$1"
    local found=""
    for dir in "$APKX_BIN_DIR" "$HOME/.apkx/bin"; do
        if [ -d "$dir" ]; then
            found=$(find "$dir" -maxdepth 1 -name "$pattern" 2>/dev/null | sort -V | tail -n 1)
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
    done
    return 1
}

init_toolchain() {
    # Android SDK Detection
    if [ -z "${ANDROID_HOME:-}" ]; then
        if [ -n "${ANDROID_SDK_ROOT:-}" ]; then
            ANDROID_HOME="$ANDROID_SDK_ROOT"
        elif [ -d "$HOME/Library/Android/sdk" ]; then
            ANDROID_HOME="$HOME/Library/Android/sdk"
        elif [ -d "$HOME/Android/Sdk" ]; then
            ANDROID_HOME="$HOME/Android/Sdk"
        elif [ -d "/opt/android-sdk" ]; then
            ANDROID_HOME="/opt/android-sdk"
        else
            ANDROID_HOME=""
        fi
    fi

    ANDROID_BUILD_TOOLS=""
    if [ -n "$ANDROID_HOME" ] && [ -d "$ANDROID_HOME/build-tools" ]; then
        local latest_bt
        latest_bt=$(ls "$ANDROID_HOME/build-tools" 2>/dev/null | sort -V | tail -n 1)
        if [ -n "$latest_bt" ]; then
            ANDROID_BUILD_TOOLS="$ANDROID_HOME/build-tools/$latest_bt"
        fi
    fi

    # ADB
    if command -v adb &>/dev/null; then
        ADB="adb"
    elif [ -n "$ANDROID_HOME" ] && [ -x "$ANDROID_HOME/platform-tools/adb" ]; then
        ADB="$ANDROID_HOME/platform-tools/adb"
    else
        ADB="adb"
    fi

    # Build-tools binaries: d8, zipalign, aapt
    if [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/d8" ]; then
        D8="$ANDROID_BUILD_TOOLS/d8"
    else
        D8="d8"
    fi

    if [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/zipalign" ]; then
        ZIPALIGN="$ANDROID_BUILD_TOOLS/zipalign"
    else
        ZIPALIGN="zipalign"
    fi

    if [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/aapt" ]; then
        AAPT="$ANDROID_BUILD_TOOLS/aapt"
    else
        AAPT="aapt"
    fi

    # JAR tools (prefer bundled bin/*.jar, fallback to system commands)
    APKTOOL_JAR="${APKX_APKTOOL_JAR:-$(find_jar "apktool*.jar" || true)}"

    if [ -n "$APKTOOL_JAR" ] && [ -f "$APKTOOL_JAR" ]; then
        APKTOOL_CMD="java -jar $APKTOOL_JAR"
        # Auto-sync publicized Android framework (1.apk) if missing
        local fw_dir
        if [[ "$OSTYPE" == "darwin"* ]]; then
            fw_dir="$HOME/Library/apktool/framework"
        else
            fw_dir="${XDG_DATA_HOME:-$HOME/.local/share}/apktool/framework"
        fi
        if [ ! -f "$fw_dir/1.apk" ]; then
            mkdir -p "$fw_dir"
            unzip -p "$APKTOOL_JAR" prebuilt/android-framework.jar > "$fw_dir/1.apk" 2>/dev/null || true
        fi
    elif command -v apktool &>/dev/null; then
        APKTOOL_CMD="apktool"
    else
        APKTOOL_CMD="java -jar $APKX_BIN_DIR/apktool.jar"
    fi

    JD_GUI_JAR=$(find_jar "jd-gui*.jar" || true)

    apksigner_jar=$(find_jar "apksigner*.jar" || true)
    if [ -n "$apksigner_jar" ] && [ -f "$apksigner_jar" ]; then
        APKSIGNER_CMD="java -jar $apksigner_jar"
    elif [ -n "$ANDROID_BUILD_TOOLS" ] && [ -f "$ANDROID_BUILD_TOOLS/lib/apksigner.jar" ]; then
        APKSIGNER_CMD="java -jar $ANDROID_BUILD_TOOLS/lib/apksigner.jar"
    elif [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/apksigner" ]; then
        APKSIGNER_CMD="$ANDROID_BUILD_TOOLS/apksigner"
    elif command -v apksigner &>/dev/null; then
        APKSIGNER_CMD="apksigner"
    else
        APKSIGNER_CMD="java -jar $APKX_BIN_DIR/apksigner.jar"
    fi

    baksmali_jar=$(find_jar "baksmali*.jar" || true)
    if [ -n "$baksmali_jar" ] && [ -f "$baksmali_jar" ]; then
        BAKSMALI_CMD="java -jar $baksmali_jar"
    elif command -v baksmali &>/dev/null; then
        BAKSMALI_CMD="baksmali"
    else
        BAKSMALI_CMD="java -jar $APKX_BIN_DIR/baksmali.jar"
    fi

    smali_jar=$(find_jar "smali*.jar" || true)
    if [ -n "$smali_jar" ] && [ -f "$smali_jar" ]; then
        SMALI_CMD="java -jar $smali_jar"
    elif command -v smali &>/dev/null; then
        SMALI_CMD="smali"
    else
        SMALI_CMD="java -jar $APKX_BIN_DIR/smali.jar"
    fi

    dx_jar=$(find_jar "dx*.jar" || true)
    if [ -n "$dx_jar" ] && [ -f "$dx_jar" ]; then
        DX_CMD="java -jar $dx_jar"
    else
        DX_CMD="java -jar $APKX_BIN_DIR/dx.jar"
    fi

    reconstruct_jar=$(find_jar "reconstruct*.jar" || true)
    if [ -n "$reconstruct_jar" ] && [ -f "$reconstruct_jar" ]; then
        RECONSTRUCT_CMD="java -jar $reconstruct_jar"
    else
        RECONSTRUCT_CMD="java -jar $APKX_BIN_DIR/reconstruct-cli.jar"
    fi

    if [ -x "$APKX_BIN_DIR/dex-tools-2.1/d2j-dex2jar.sh" ]; then
        D2J_DEX2JAR="$APKX_BIN_DIR/dex-tools-2.1/d2j-dex2jar.sh"
    elif command -v d2j-dex2jar &>/dev/null; then
        D2J_DEX2JAR="d2j-dex2jar"
    elif command -v d2j-dex2jar.sh &>/dev/null; then
        D2J_DEX2JAR="d2j-dex2jar.sh"
    else
        D2J_DEX2JAR="$APKX_BIN_DIR/dex-tools-2.1/d2j-dex2jar.sh"
    fi

    JADX_CMD="${JADX_CMD:-jadx}"

    # Signing Keystore Configuration (standard Android debug keystore defaults; auto-generated if missing)
    APKX_KEYSTORE="${APKX_KEYSTORE:-$APKX_BIN_DIR/debug.keystore}"
    APKX_KEY_ALIAS="${APKX_KEY_ALIAS:-androiddebugkey}"
    APKX_KEY_PASS="${APKX_KEY_PASS:-pass:android}"
    APKX_KS_PASS="${APKX_KS_PASS:-pass:android}"
}

# ── Project Context & Configuration Loading ──────────────────────────────────
init_project_context() {
    TARGET_ARG="${1:-}"
    APK_FILE="$TARGET_ARG"

    APKTOOL_YML=""
    if [ -f "smali/apktool.yml" ]; then
        APKTOOL_YML="smali/apktool.yml"
    elif [ -f "apktool.yml" ]; then
        APKTOOL_YML="apktool.yml"
    else
        APKTOOL_YML=$(find . -maxdepth 3 -name 'apktool.yml' 2>/dev/null | head -n 1 || true)
    fi

    PROJ_DIR="${PWD##*/}"
    if [ -n "$APKTOOL_YML" ]; then
        PROJ_DIR=$(dirname "$APKTOOL_YML")
    fi

    VERSION=""
    APP_MAJOR_MINOR=""
    VERSION_CODE=""

    if [ -n "$APKTOOL_YML" ] && [ -f "$APKTOOL_YML" ]; then
        APP_MAJOR_MINOR=$(grep -Eo "^ *versionName: *.*" "$APKTOOL_YML" 2>/dev/null | awk -F ': ' '{print $2}' | tr -d "'\"" | cut -f1,2 -d'.' | xargs || true)
        VERSION_CODE="${APP_MAJOR_MINOR//./}"
    fi

    # Load user/project configuration if present (after VERSION_CODE is resolved)
    # Search order: ~/.apkx/config -> ../.apkx.conf -> ./.apkx.conf
    for cfg in "$HOME/.apkx/config" "../.apkx.conf" "./.apkx.conf"; do
        if [ -f "$cfg" ]; then
            # shellcheck disable=SC1090
            source "$cfg"
        fi
    done

    PLUGIN_DIR="${PLUGIN_DIR:-../../AppPlugin}"
    GOLANG_DIR="${GOLANG_DIR:-../../AppNative}"
    PLUGIN_BASE_MODULE="${PLUGIN_BASE_MODULE:-plugin}"
    PLUGIN_TARGET_PREFIX="${PLUGIN_TARGET_PREFIX:-app}"
    PLUGIN_GRADLE_PROP_NAME="${PLUGIN_GRADLE_PROP_NAME:-targetVersion}"
    PLUGIN_MODULE="${PLUGIN_MODULE:-${PLUGIN_BASE_MODULE}${VERSION_CODE}}"
    PLUGIN_TARGET_MODULE="${PLUGIN_TARGET_MODULE:-${PLUGIN_TARGET_PREFIX}${VERSION_CODE}}"
    SMALI_INJECT_DIR="${SMALI_INJECT_DIR:-smali_classes2}"
    BASE_APP_ID_PREFIX="${BASE_APP_ID_PREFIX:-com.example}"
}

# Resolve target APK file path for current project or argument
resolve_apk_file() {
    if [ -n "${APK_FILE:-}" ] && [ -f "$APK_FILE" ]; then
        echo "$APK_FILE"
        return 0
    fi
    if [ -n "${APK_FILE:-}" ] && [ -d "$APK_FILE" ]; then
        echo "$(basename "$APK_FILE").apk"
        return 0
    fi
    # Check Gradle project outputs if present
    if [ -f "app/build/outputs/apk/debug/app-debug.apk" ]; then
        echo "app/build/outputs/apk/debug/app-debug.apk"
        return 0
    fi
    echo "$(basename "$PWD").apk"
}

# Extract package name from APK or Gradle config
resolve_package_name() {
    local apk="${1:-$(resolve_apk_file)}"
    if [ -f "$apk" ] && command -v "$AAPT" &>/dev/null; then
        local pkg
        pkg=$("$AAPT" dump badging "$apk" 2>/dev/null | head -n 1 | grep -oE "name='[^']+'" | head -n 1 | cut -d"'" -f2 || true)
        if [ -n "$pkg" ]; then
            echo "$pkg"
            return 0
        fi
    fi
    if [ -f "smali/AndroidManifest.xml" ]; then
        local pkg
        pkg=$(grep -oE 'package="[^"]+"' "smali/AndroidManifest.xml" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
        if [ -n "$pkg" ]; then
            echo "$pkg"
            return 0
        fi
    fi
    if [ -f "app/build.gradle.kts" ]; then
        local pkg
        pkg=$(grep -oE 'applicationId\s*=\s*"[^"]+"' "app/build.gradle.kts" 2>/dev/null | head -n 1 | cut -d'"' -f2 || true)
        if [ -n "$pkg" ]; then
            echo "$pkg"
            return 0
        fi
    fi
    echo "${APKX_PACKAGE:-}"
}
