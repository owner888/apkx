#!/usr/bin/env bash
# ============================================================================
# apkx — Environment Doctor, Dependency Setup & Framework Management
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

APKTOOL_DEFAULT_VER="3.0.3"
SMALI_DEFAULT_VER="2.5.2"

check_cmd_status() {
    local label="$1"
    local cmd_path="$2"
    local hint="$3"

    if [ -n "$cmd_path" ] && { [ -f "$cmd_path" ] || command -v "$cmd_path" &>/dev/null; }; then
        printf "  ${GREEN}✔${NC} %-22s %s\n" "$label" "${DIM}${cmd_path}${NC}"
        return 0
    else
        printf "  ${YELLOW}⚠${NC} %-22s ${YELLOW}missing${NC} ${DIM}(%s)${NC}\n" "$label" "$hint"
        return 1
    fi
}

cmd_doctor() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━ apkx Environment Doctor ━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}APKX_HOME:${NC}        ${APKX_HOME}"
    echo -e "  ${BOLD}APKX_BIN_DIR:${NC}     ${APKX_BIN_DIR}"
    echo -e "  ${BOLD}ANDROID_HOME:${NC}     ${ANDROID_HOME:-not detected}"
    echo -e "  ${BOLD}BUILD_TOOLS:${NC}      ${ANDROID_BUILD_TOOLS:-not detected}"
    echo ""

    echo -e "  ${BOLD}System & Android SDK Tools:${NC}"
    check_cmd_status "java" "$(command -v java || true)" "Install JDK 11+" || true
    check_cmd_status "adb" "$(command -v "$ADB" || true)" "Android SDK Platform-Tools" || true
    check_cmd_status "aapt" "$(command -v "$AAPT" || true)" "Android SDK Build-Tools" || true
    check_cmd_status "d8" "$(command -v "$D8" || true)" "Android SDK Build-Tools" || true
    check_cmd_status "zipalign" "$(command -v "$ZIPALIGN" || true)" "Android SDK Build-Tools" || true
    check_cmd_status "jadx" "$(command -v "$JADX_CMD" || true)" "brew install jadx" || true
    check_cmd_status "go (optional)" "$(command -v go || true)" "brew install go" || true
    check_cmd_status "gomobile (optional)" "$(command -v gomobile || true)" "go install golang.org/x/mobile/cmd/gomobile@latest" || true

    echo ""
    echo -e "  ${BOLD}Reverse & Repackaging JARs (${APKX_BIN_DIR}):${NC}"
    local apktool_jar apksigner_jar baksmali_jar smali_jar
    apktool_jar="${APKTOOL_JAR:-$(find_jar "apktool*.jar" || command -v apktool || true)}"
    apksigner_jar=$(find_jar "apksigner*.jar" || command -v apksigner || true)
    if [ -z "$apksigner_jar" ] && [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/apksigner" ]; then
        apksigner_jar="$ANDROID_BUILD_TOOLS/apksigner"
    fi
    baksmali_jar=$(find_jar "baksmali*.jar" || command -v baksmali || true)
    smali_jar=$(find_jar "smali*.jar" || command -v smali || true)

    check_cmd_status "apktool" "$apktool_jar" "Run: apkx setup" || true
    check_cmd_status "apksigner" "$apksigner_jar" "Android SDK Build-Tools or apkx setup" || true
    check_cmd_status "baksmali" "$baksmali_jar" "Run: apkx setup" || true
    check_cmd_status "smali" "$smali_jar" "Run: apkx setup" || true
    check_cmd_status "dex2jar" "$(command -v "$D2J_DEX2JAR" || find_jar "dex-tools*" || true)" "Optional for s2j" || true
    check_cmd_status "jd-gui" "${JD_GUI_JAR:-}" "Bundled in bin/" || true
    check_cmd_status "debug.keystore" "$APKX_KEYSTORE" "Auto-generated on build or apkx setup" || true

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

ensure_keystore() {
    if [ -f "$APKX_KEYSTORE" ]; then
        return 0
    fi
    mkdir -p "$(dirname "$APKX_KEYSTORE")"
    if command -v keytool &>/dev/null; then
        info "Generating default debug keystore at ${APKX_KEYSTORE}..."
        local raw_pass="${APKX_KEY_PASS#pass:}"
        local raw_ks_pass="${APKX_KS_PASS#pass:}"
        keytool -genkeypair \
            -keystore "$APKX_KEYSTORE" \
            -alias "$APKX_KEY_ALIAS" \
            -keyalg RSA \
            -keysize 2048 \
            -validity 10000 \
            -storepass "$raw_ks_pass" \
            -keypass "$raw_pass" \
            -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
        ok "Generated debug keystore: ${APKX_KEYSTORE}"
    else
        warn "keytool not found; cannot auto-generate debug.keystore"
    fi
}

cmd_setup() {
    local link_from="${1:-}"
    mkdir -p "$APKX_BIN_DIR"

    if [ "$link_from" = "--from" ] || [ "$link_from" = "--link" ]; then
        local src_dir="${2:-}"
        [ -z "$src_dir" ] || [ ! -d "$src_dir" ] && fail "Source directory not found: ${src_dir}"
        src_dir="$(cd "$src_dir" && pwd)"
        info "Linking tools from ${src_dir} into ${APKX_BIN_DIR}..."
        for item in "$src_dir"/*; do
            [ -e "$item" ] || continue
            ln -sfn "$item" "$APKX_BIN_DIR/$(basename "$item")"
        done
        ok "Linked all binaries/JARs into ${APKX_BIN_DIR}"
        ensure_keystore
        cmd_doctor
        return 0
    fi

    info "Setting up apkx toolchain in ${APKX_BIN_DIR}..."

    # 1. Apktool JAR
    if ! find_jar "apktool*.jar" >/dev/null; then
        local apktool_url="https://github.com/iBotPeaches/Apktool/releases/download/v${APKTOOL_DEFAULT_VER}/apktool_${APKTOOL_DEFAULT_VER}.jar"
        info "Downloading apktool_${APKTOOL_DEFAULT_VER}.jar..."
        curl -fL --progress-bar "$apktool_url" -o "$APKX_BIN_DIR/apktool_${APKTOOL_DEFAULT_VER}.jar"
        ok "Downloaded apktool_${APKTOOL_DEFAULT_VER}.jar"
    else
        ok "apktool JAR already exists: $(find_jar "apktool*.jar")"
    fi

    # 2. baksmali & smali JARs
    if ! find_jar "baksmali*.jar" >/dev/null; then
        local baksmali_url="https://bitbucket.org/JesusFreke/smali/downloads/baksmali-${SMALI_DEFAULT_VER}.jar"
        info "Downloading baksmali-${SMALI_DEFAULT_VER}.jar..."
        curl -fL --progress-bar "$baksmali_url" -o "$APKX_BIN_DIR/baksmali-${SMALI_DEFAULT_VER}.jar" || \
            warn "Could not download baksmali automatically"
    else
        ok "baksmali JAR already exists: $(find_jar "baksmali*.jar")"
    fi

    if ! find_jar "smali*.jar" >/dev/null; then
        local smali_url="https://bitbucket.org/JesusFreke/smali/downloads/smali-${SMALI_DEFAULT_VER}.jar"
        info "Downloading smali-${SMALI_DEFAULT_VER}.jar..."
        curl -fL --progress-bar "$smali_url" -o "$APKX_BIN_DIR/smali-${SMALI_DEFAULT_VER}.jar" || \
            warn "Could not download smali automatically"
    else
        ok "smali JAR already exists: $(find_jar "smali*.jar")"
    fi

    # 3. Keystore
    ensure_keystore

    init_toolchain
    cmd_doctor
}

cmd_framework() {
    local fw_apk="${1:-}"
    if [ -n "$fw_apk" ]; then
        [ ! -f "$fw_apk" ] && fail "Framework APK not found: ${fw_apk}"
        info "Installing custom framework APK (${fw_apk}) via apktool..."
        $APKTOOL_CMD if "$fw_apk"
        ok "Framework installed successfully"
        return 0
    fi

    if [ -z "${APKTOOL_JAR:-}" ] || [ ! -f "$APKTOOL_JAR" ]; then
        fail "Bundled apktool JAR not found"
    fi

    local fw_dir
    if [[ "$OSTYPE" == "darwin"* ]]; then
        fw_dir="$HOME/Library/apktool/framework"
    else
        fw_dir="${XDG_DATA_HOME:-$HOME/.local/share}/apktool/framework"
    fi
    mkdir -p "$fw_dir"
    info "Extracting publicized Android framework from $(basename "$APKTOOL_JAR") -> ${fw_dir}/1.apk ..."
    unzip -p "$APKTOOL_JAR" prebuilt/android-framework.jar > "$fw_dir/1.apk"
    ok "Installed publicized framework: ${fw_dir}/1.apk"
}
