#!/usr/bin/env bash
# ============================================================================
# apkx — APK Repackaging, AAR/Plugin/Native Injection & Multi-Variant Builds
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

# Read version string from Version.smali if present
read_version() {
    if [ ! -d "smali/$SMALI_INJECT_DIR/com" ]; then
        return 0
    fi
    local version_path
    version_path=$(find "smali/$SMALI_INJECT_DIR/com" -name "Version.smali" 2>/dev/null | head -n 1 || true)
    if [ -z "$version_path" ] || [ ! -f "$version_path" ]; then
        return 0
    fi
    VERSION=$(grep -Eo '"V[0-9]+(\.[0-9]+)*"' "$version_path" 2>/dev/null | tr -d '"' | head -n 1 || true)
}

# Stamp current Git commit hash and build timestamp into Version.smali
write_build_version() {
    if [ ! -d "smali/$SMALI_INJECT_DIR/com" ]; then
        return 0
    fi
    local version_path
    version_path=$(find "smali/$SMALI_INJECT_DIR/com" -name "Version.smali" 2>/dev/null | head -n 1 || true)
    if [ -z "$version_path" ] || [ ! -f "$version_path" ]; then
        return 0
    fi
    local build_hash build_date
    build_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "00000000")
    build_date=$(date '+%Y-%m-%d %H:%M')
    sed_regex_inplace -e "s/[0-9a-f]{7,8}/$build_hash/g" "$version_path"
    sed_regex_inplace -e "s/[0-9 :-]{16}/$build_date/g" "$version_path"
    info "Version stamp: ${CYAN}${VERSION} Build ${build_hash} (${build_date})${NC}"
}

# Build APK from decoded smali directory (or Gradle project if applicable)
# Args: $1 = debug_flag ("-d" or "")
#       $2 = custom_app_id (optional)
#       $3 = filename_suffix (optional)
cmd_build() {
    local debug_flag="${1:-}"
    local app_id="${2:-}"
    local suffix="${3:-}"

    # Support Gradle projects seamlessly if no smali directory exists
    if [ ! -d "smali" ] && [ -z "${APK_FILE:-}" ] && [ -x "./gradlew" ]; then
        build_gradle_project
        return $?
    fi

    read_version
    if { [ -d "../.git" ] || [ -d ".git" ]; } && [ -n "$VERSION" ]; then
        write_build_version
    fi

    if [ -n "${APK_FILE:-}" ] && [ -d "$APK_FILE" ]; then
        cd "$APK_FILE"
    fi

    local apk_file_name
    apk_file_name="$(basename "$PWD").apk"
    if [ -n "$suffix" ]; then
        apk_file_name="${apk_file_name/%.apk/_${suffix}.apk}"
    fi

    local smali_root="smali"
    if [ ! -d "$smali_root" ] && [ -f "apktool.yml" ]; then
        smali_root="."
    fi

    if [ ! -d "$smali_root" ]; then
        fail "Decoded smali directory not found in ${PWD}"
    fi

    info "Compiling APK... ${app_id:+[AppID: $app_id] }${suffix:+[Suffix: $suffix]}"
    rm -rf "$smali_root/build"

    # Migrate legacy API-23 mis-decoded Material 3 dynamic color names to API-34+ official names if present
    if [ -d "$smali_root/res" ] && grep -rq "@android:color/Teal_800\|@android:color/Blue_700\|@android:color/accent_device_default_700" "$smali_root/res" 2>/dev/null; then
        find "$smali_root/res" -name "colors.xml" -print0 2>/dev/null | xargs -0 perl -pi -e '
            s|\@android:color/Blue_700|\@android:color/system_primary_container_light|g;
            s|\@android:color/Blue_800|\@android:color/system_on_primary_container_light|g;
            s|\@android:color/Indigo_700|\@android:color/system_on_primary_light|g;
            s|\@android:color/Indigo_800|\@android:color/system_secondary_container_light|g;
            s|\@android:color/Pink_700|\@android:color/system_on_secondary_container_light|g;
            s|\@android:color/Pink_800|\@android:color/system_secondary_light|g;
            s|\@android:color/Purple_700|\@android:color/system_on_secondary_light|g;
            s|\@android:color/Purple_800|\@android:color/system_tertiary_container_light|g;
            s|\@android:color/Red_700|\@android:color/system_on_tertiary_container_light|g;
            s|\@android:color/Red_800|\@android:color/system_tertiary_light|g;
            s|\@android:color/Teal_700|\@android:color/system_on_tertiary_light|g;
            s|\@android:color/Teal_800|\@android:color/system_background_light|g;
            s|\@android:color/accent_device_default_50|\@android:color/system_surface_light|g;
            s|\@android:color/accent_device_default_700|\@android:color/system_on_surface_light|g;
            s|\@android:color/accent_device_default_dark_60_percent_opacity|\@android:color/system_surface_container_lowest_light|g;
        '
    fi

    local find_str=""
    if { [ -d "../.git" ] || [ -d ".git" ]; } && [ -n "$VERSION" ] && [ -n "$app_id" ]; then
        find_str="${BASE_APP_ID_PREFIX}.${PLUGIN_TARGET_MODULE}"
        if [ -f "$smali_root/AndroidManifest.xml" ]; then
            sed_inplace -e "s/$find_str/${app_id}/g" "$smali_root/AndroidManifest.xml"
        fi
        if [ -f "$smali_root/res/xml/shortcuts.xml" ]; then
            sed_inplace -e "s/$find_str/${app_id}/g" "$smali_root/res/xml/shortcuts.xml"
        fi
    elif [ -n "$app_id" ] && [ -f "$smali_root/AndroidManifest.xml" ]; then
        find_str=$(grep -oE 'package="[^"]+"' "$smali_root/AndroidManifest.xml" | head -n 1 | cut -d'"' -f2 || true)
        if [ -n "$find_str" ]; then
            sed_inplace -e "s/$find_str/${app_id}/g" "$smali_root/AndroidManifest.xml"
            [ -f "$smali_root/res/xml/shortcuts.xml" ] && sed_inplace -e "s/$find_str/${app_id}/g" "$smali_root/res/xml/shortcuts.xml"
        fi
    fi

    local start_time=$SECONDS
    if [ "$debug_flag" = "-d" ]; then
        debug_flag="--debuggable"
    fi
    if [ -n "$debug_flag" ]; then
        $APKTOOL_CMD b "$smali_root" -f "$debug_flag" -o "$apk_file_name"
    else
        $APKTOOL_CMD b "$smali_root" -f -o "$apk_file_name"
    fi

    # Restore original package name in manifest & shortcuts
    if [ -n "$app_id" ] && [ -n "$find_str" ]; then
        [ -f "$smali_root/AndroidManifest.xml" ] && sed_inplace -e "s/${app_id}/${find_str}/g" "$smali_root/AndroidManifest.xml"
        [ -f "$smali_root/res/xml/shortcuts.xml" ] && sed_inplace -e "s/${app_id}/${find_str}/g" "$smali_root/res/xml/shortcuts.xml"
    fi

    # Zipalign 4
    mv "$apk_file_name" "${apk_file_name}_tmp"
    "$ZIPALIGN" -f 4 "${apk_file_name}_tmp" "$apk_file_name"
    rm -rf "${apk_file_name}_tmp"

    # Sign APK
    ensure_keystore
    $APKSIGNER_CMD sign \
        --ks "$APKX_KEYSTORE" \
        --ks-key-alias "$APKX_KEY_ALIAS" \
        --ks-pass "$APKX_KS_PASS" \
        --key-pass "$APKX_KEY_PASS" \
        --out "$apk_file_name" \
        "$apk_file_name"
    rm -rf "${apk_file_name}.idsig"

    local elapsed=$(( SECONDS - start_time ))
    local size
    size=$(du -h "$apk_file_name" | awk '{print $1}')
    ok "Compiled & signed: ${GREEN}${apk_file_name}${NC} (${size}, ${elapsed}s)"
}

# Build standard Gradle Android project when used inside an Android Studio repo
build_gradle_project() {
    local clean_arg="${1:-}"
    local start_time=$SECONDS
    info "Building Gradle debug APK..."

    ./gradlew ${clean_arg} assembleDebug --no-configuration-cache --console=plain 2>&1 | while IFS= read -r line; do
        if echo "$line" | grep -qiE "^e:|error|FAILURE|exception"; then
            echo -e "  ${RED}$line${NC}"
        elif echo "$line" | grep -qiE "^w:|warning"; then
            echo -e "  ${YELLOW}$line${NC}"
        elif echo "$line" | grep -qE "BUILD SUCCESSFUL"; then
            echo -e "  ${GREEN}$line${NC}"
        fi
    done

    local apk_out="app/build/outputs/apk/debug/app-debug.apk"
    if [ ! -f "$apk_out" ]; then
        fail "Gradle APK was not generated. Check compiler errors above."
    fi
    local elapsed=$(( SECONDS - start_time ))
    local size
    size=$(du -h "$apk_out" | awk '{print $1}')
    ok "Gradle build complete: ${GREEN}${apk_out}${NC} (${size}, ${elapsed}s)"
}

# Inject an AAR package (classes.jar + res + jni) into target smali_classesN directory
# Args: $1 = path/to/file.aar, $2 = target_smali_dir (default: smali_classes2), $3 = optional hook function
cmd_inject_aar() {
    local aar_path="${1:-}"
    local smali_dir="${2:-$SMALI_INJECT_DIR}"
    local hook_fn="${3:-}"

    if [ -z "$aar_path" ] || [ ! -f "$aar_path" ]; then
        fail "AAR file not found: ${aar_path:-<none>}"
    fi

    info "Injecting AAR $(basename "$aar_path") -> smali/${smali_dir} ..."
    local original_dir="$PWD"
    local aar_dir
    aar_dir=$(dirname "$aar_path")
    local aar_name
    aar_name=$(basename "$aar_path")

    (
        cd "$aar_dir"
        unzip -q -o "$aar_name"
        "$D8" --min-api 24 --output "${aar_name}.zip" classes.jar
        unzip -q -o "${aar_name}.zip"
        rm -rf "$smali_dir"
        $BAKSMALI_CMD d --di false -o "$smali_dir" classes.dex
        find "$smali_dir" -name "BuildConfig.smali" -delete 2>/dev/null || true

        # Move root defpackage classes into L...
        find "$smali_dir" -name '*.smali' -print0 2>/dev/null | \
            xargs -0 -P 8 -n 200 perl -pi -e 's/Ldefpackage\//L/g'

        if [ -n "$hook_fn" ]; then
            "$hook_fn" "$smali_dir"
        fi

        if [ -e "$smali_dir/defpackage" ]; then
            mv "$smali_dir/defpackage/"* "$original_dir/smali/smali/"
        fi
        cp -a "$smali_dir" "$original_dir/smali/"
        if [ -e "res/values" ]; then
            rm -rf res/values*
        fi
        if [ -e "res" ]; then
            cp -a res "$original_dir/smali/"
        fi
        if [ -e "jni/" ]; then
            cp -a jni/ "$original_dir/smali/lib/"
        fi
    )
    ok "Injected AAR $(basename "$aar_path") successfully"
}

# Compile Java/Kotlin Gradle plugin modules and inject into smali
cmd_plugin() {
    if [ ! -d "$PLUGIN_DIR" ]; then
        warn "Plugin directory not found: ${PLUGIN_DIR} (configure PLUGIN_DIR in .apkx.conf)"
        return 0
    fi

    info "Building & injecting Java plugin from ${PLUGIN_DIR}/${PLUGIN_MODULE} ..."
    local original_dir="$PWD"
    local base_mod="$PLUGIN_BASE_MODULE"

    (
        cd "$PLUGIN_DIR"
        local proguard_arg=""
        if [ -e "${PLUGIN_MODULE}/proguard-rules.pro" ]; then
            proguard_arg="-PproguardRules=../${PLUGIN_MODULE}/proguard-rules.pro"
        fi
        ./gradlew clean "${base_mod}:assembleRelease" $proguard_arg "-P${PLUGIN_GRADLE_PROP_NAME}=${PLUGIN_TARGET_MODULE}"
    )
    cmd_inject_aar "$PLUGIN_DIR/${base_mod}/build/outputs/aar/${base_mod}-release.aar" "$SMALI_INJECT_DIR"
    cp -a "$PLUGIN_DIR/${base_mod}/src/main/res/values"* "$original_dir/smali/res/" 2>/dev/null || true

    if [ -d "$PLUGIN_DIR/$PLUGIN_MODULE" ]; then
        (
            cd "$PLUGIN_DIR"
            ./gradlew clean "${PLUGIN_MODULE}:assembleRelease" "-P${PLUGIN_GRADLE_PROP_NAME}=${PLUGIN_TARGET_MODULE}"
        )
        cmd_inject_aar "$PLUGIN_DIR/${PLUGIN_MODULE}/build/outputs/aar/${PLUGIN_MODULE}-release.aar" "$SMALI_INJECT_DIR"
        cp -a "$PLUGIN_DIR/${PLUGIN_MODULE}/src/main/res/values"* "$original_dir/smali/res/" 2>/dev/null || true
    fi
}

# Compile Go Native (gomobile/gobind) library and inject into plugin & smali
cmd_native() {
    local gmflags=""
    for arg in "$@"; do
        case "$arg" in
            gmflags=*) gmflags="${arg#gmflags=}" ;;
        esac
    done

    if [ ! -d "$GOLANG_DIR" ]; then
        warn "Go native project not found: ${GOLANG_DIR} (configure GOLANG_DIR in .apkx.conf)"
        return 0
    fi
    if ! command -v go &>/dev/null; then
        fail "go command not found. Install Go first: brew install go"
    fi
    if ! command -v gomobile &>/dev/null; then
        info "Installing gomobile..."
        go install golang.org/x/mobile/cmd/gomobile@latest
    fi
    if ! command -v gobind &>/dev/null; then
        info "Installing gobind..."
        go install golang.org/x/mobile/cmd/gobind@latest
    fi

    info "Compiling Go native library (${GOLANG_DIR}) -> ${PLUGIN_DIR}"
    local original_dir="$PWD"
    local golang_build_dir="build"
    local golang_pkg_name="${PLUGIN_BASE_MODULE:-plugin}"
    local aar_output="${golang_build_dir}/${golang_pkg_name}.aar"

    (
        cd "$GOLANG_DIR"
        rm -rf "$golang_build_dir"
        mkdir -p "$golang_build_dir"
        go version
        info "Compiling Android arm64 .so via gomobile..."
        # shellcheck disable=SC2086
        gomobile bind -o "$aar_output" -target=android/arm64 -androidapi 21 -v -trimpath -ldflags "-s -w" ${gmflags} .
        if declare -f apkx_after_native_bind >/dev/null 2>&1; then
            apkx_after_native_bind "$aar_output"
        fi
    )

    if [ -d "$PLUGIN_DIR/$golang_pkg_name" ]; then
        (
            info "Copying generated Java bindings into plugin project..."
            cd "$GOLANG_DIR/$golang_build_dir"
            unzip -q -o "${golang_pkg_name}-sources.jar"
            find "go" -name '*.java' -print0 2>/dev/null | while IFS= read -r -d '' jf; do
                sed_inplace -e "s/\"gojni\"/\"${golang_pkg_name}\"/g" "$jf"
            done
            cp -a "$golang_pkg_name" "$PLUGIN_DIR/${golang_pkg_name}/src/main/java/"
            cp -a go "$PLUGIN_DIR/${golang_pkg_name}/src/main/java/"
        )
        (
            info "Copying libgojni.so -> lib${golang_pkg_name}.so..."
            cd "$GOLANG_DIR/$golang_build_dir"
            unzip -q -o "${golang_pkg_name}.aar"
            if [ -d "$original_dir/smali/lib/arm64-v8a" ]; then
                cp "jni/arm64-v8a/libgojni.so" "$original_dir/smali/lib/arm64-v8a/lib${golang_pkg_name}.so"
            fi
            mkdir -p "$PLUGIN_DIR/${golang_pkg_name}/src/main/jniLibs/arm64-v8a"
            cp "jni/arm64-v8a/libgojni.so" "$PLUGIN_DIR/${golang_pkg_name}/src/main/jniLibs/arm64-v8a/lib${golang_pkg_name}.so"
        )
    fi

    ok "Injected Go native library successfully"
}

# Standalone zipalign (-p 4) + apksigner sign for any existing APK file
cmd_sign() {
    local target="${1:-$(resolve_apk_file)}"
    [ -z "$target" ] || [ ! -f "$target" ] && fail "APK file not found: ${target:-<none>}"

    info "Aligning & signing ${CYAN}${target}${NC} ..."
    local tmp_aligned="${target%.apk}_aligned_tmp.apk"

    if command -v "$ZIPALIGN" &>/dev/null || [ -x "$ZIPALIGN" ]; then
        "$ZIPALIGN" -p -f 4 "$target" "$tmp_aligned"
    else
        cp "$target" "$tmp_aligned"
    fi

    ensure_keystore
    $APKSIGNER_CMD sign \
        --ks "$APKX_KEYSTORE" \
        --ks-key-alias "$APKX_KEY_ALIAS" \
        --ks-pass "$APKX_KS_PASS" \
        --key-pass "$APKX_KEY_PASS" \
        --out "$target" \
        "$tmp_aligned"

    rm -rf "$tmp_aligned" "${target}.idsig"
    ok "Signed successfully: ${GREEN}${target}${NC}"
}

# Full release package (Native + Plugin + Release Build)
cmd_package() {
    cmd_native
    cmd_plugin
    cmd_build
}

# Build a single named variant from APKX_VARIANTS or suffix:package spec
cmd_variant() {
    local target_var="${1:-}"
    [ -z "$target_var" ] && fail "Usage: apkx --variant <name|suffix:applicationId>"

    cmd_native
    cmd_plugin
    read_version

    if [[ "$target_var" == *":"* ]]; then
        cmd_build "" "${target_var#*:}" "${VERSION}_${target_var%%:*}"
        return 0
    fi

    if [ "${#APKX_VARIANTS[@]}" -gt 0 ] 2>/dev/null; then
        local entry suffix pkg
        for entry in "${APKX_VARIANTS[@]}"; do
            suffix="${entry%%:*}"
            pkg="${entry#*:}"
            if [ "$suffix" = "$target_var" ]; then
                cmd_build "" "$pkg" "${VERSION}_${suffix}"
                return 0
            fi
        done
    fi

    fail "Variant '${target_var}' not found in APKX_VARIANTS (.apkx.conf)"
}

# Build all configured variants in APKX_VARIANTS
cmd_package_all_variants() {
    cmd_native
    cmd_plugin
    read_version

    cmd_build "" "" "${VERSION}"
    if [ "${#APKX_VARIANTS[@]}" -gt 0 ] 2>/dev/null; then
        local entry suffix pkg
        for entry in "${APKX_VARIANTS[@]}"; do
            suffix="${entry%%:*}"
            pkg="${entry#*:}"
            cmd_build "" "$pkg" "${VERSION}_${suffix}"
        done
    else
        warn "No APKX_VARIANTS configured in .apkx.conf; built default package only."
    fi
}
