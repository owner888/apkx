#!/usr/bin/env bash
# ============================================================================
# apkx — APK Decompilation & Split Bundle (APKM/XAPK/APKS) Conversion
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

cmd_decode() {
    local target="${1:-${APK_FILE:-}}"
    if [ -z "$target" ] || [ ! -f "$target" ]; then
        fail "Target APK file not found: ${target:-<none>}"
    fi

    local apk_base_dir="${target%.*}"
    mkdir -p "$apk_base_dir"

    # If target is a split bundle (.apkm/.xapk/.apks), convert it AND reuse its decoded smali dir directly
    if [[ "$target" =~ \.(apkm|xapk|apks)$ ]]; then
        cmd_convert "$target" "$apk_base_dir/smali"
        target="${target%.*}.apk"
    else
        info "Decoding resources & smali with apktool -> ${apk_base_dir}/smali ..."
        $APKTOOL_CMD d -f "$target" -o "$apk_base_dir/smali"
        ok "Decompiled smali & resources successfully"
    fi

    if [ "${2:-}" != "--no-adjust" ] && [ "${2:-}" != "--raw" ]; then
        cmd_adjust_smali "$apk_base_dir"
    fi

    if command -v "$JADX_CMD" &>/dev/null; then
        info "Decompiling Java sources with jadx (-r, code only) -> ${apk_base_dir}/source ..."
        "$JADX_CMD" -r --show-bad-code -e "$target" -d "$apk_base_dir/source" || true
        prune_jadx_source_dir "${apk_base_dir}/source"
        ok "Decompiled Java sources (defpackage only) -> ${GREEN}${apk_base_dir}/source/app/src/main/java/defpackage${NC}"
    else
        warn "jadx not found, skipped Java source decompilation"
    fi
}

cmd_convert() {
    local target="${1:-${APK_FILE:-}}"
    local keep_smali_dir="${2:-}"
    if [ -z "$target" ] || [ ! -f "$target" ]; then
        fail "Target split package (APKM/XAPK/APKS) not found: ${target:-<none>}"
    fi

    info "Converting split package (${target}) to standalone APK..."

    local apk_base_name
    apk_base_name=$(basename "${target%.*}")
    local target_apk="${target%.*}.apk"
    local tmp_output="${TMPDIR:-/tmp/}apkx_convert_${apk_base_name}_$$"
    rm -rf "$tmp_output"
    mkdir -p "$tmp_output"

    unzip -o -q -d "$tmp_output" "$target"

    # 1. Auto-detect Base APK
    local base_apk=""
    if [ -f "$tmp_output/manifest.json" ]; then
        base_apk=$(grep -Eo '"file":"[^"]+","id":"base"' "$tmp_output/manifest.json" 2>/dev/null | cut -d'"' -f4 || true)
    fi
    if [ -z "$base_apk" ] || [ ! -f "$tmp_output/$base_apk" ]; then
        if [ -f "$tmp_output/base.apk" ]; then
            base_apk="base.apk"
        else
            base_apk=$(cd "$tmp_output" && ls -S ./*.apk 2>/dev/null | sed 's|^\./||' | grep -v '^config\.' | head -n 1 || true)
            if [ -z "$base_apk" ]; then
                base_apk=$(cd "$tmp_output" && ls -S ./*.apk 2>/dev/null | sed 's|^\./||' | head -n 1 || true)
            fi
        fi
    fi

    if [ -z "$base_apk" ] || [ ! -f "$tmp_output/$base_apk" ]; then
        rm -rf "$tmp_output"
        fail "No base APK found in ${target}"
    fi

    info "Base APK detected: ${CYAN}${base_apk}${NC}"
    local base_src="$tmp_output/base_src"
    $APKTOOL_CMD d -f -o "$base_src" "$tmp_output/$base_apk"

    # 2. Merge native libraries (lib/) and essential assets/ from split APKs
    #    Skip Pixel-generation TPU/HAL split assets (*_p2[0-9]*, *_p3[0-9]*, *releasekeys*, device codenames)
    #    so this works automatically on future Google Camera 12 / 13 / 14+ releases.
    local split_apk
    for split_apk in $(cd "$tmp_output" && find . -maxdepth 1 -name "*.apk" ! -name "$base_apk" | sort); do
        split_apk="${split_apk#./}"
        local apk_dir="$tmp_output/split_${split_apk%.*}"
        mkdir -p "$apk_dir"

        # Always extract native .so libraries (lib/*) from split APKs
        unzip -o -q -d "$apk_dir" "$tmp_output/$split_apk" "lib/*" 2>/dev/null || true
        if [ -d "$apk_dir/lib" ]; then
            mkdir -p "$base_src/lib"
            cp -a "$apk_dir/lib/"* "$base_src/lib/"
            info "Merged split lib/: ${split_apk}"
        fi

        # Only extract assets/* from generic (non-Pixel-TPU / non-HAL) asset modules
        case "$split_apk" in
            split_camera_vkp_asset_module.apk|split_portrait_asset_module.apk)
                unzip -o -q -d "$apk_dir" "$tmp_output/$split_apk" "assets/*" 2>/dev/null || true
                if [ -d "$apk_dir/assets" ]; then
                    mkdir -p "$base_src/assets"
                    cp -a "$apk_dir/assets/"* "$base_src/assets/"
                    info "Merged split assets/: ${split_apk}"
                fi
                ;;
            split_all_in_*)
                unzip -o -q -d "$apk_dir" "$tmp_output/$split_apk" \
                    "assets/face_attributes_client_options.pb.uncompressed" \
                    "assets/all_in_*_assets_processed_manifest/*" \
                    "assets/all_in_*_assets_symbols/*" 2>/dev/null || true
                if [ -d "$apk_dir/assets" ]; then
                    mkdir -p "$base_src/assets"
                    cp -a "$apk_dir/assets/"* "$base_src/assets/"
                fi
                ;;
            split_portrait_asset_module_*.apk|split_camera_*_asset_module.apk|*_[pP][2-9][0-9]*|*releasekeys*|*geo_cal*|*made_you_look*)
                # Skip device-specific Pixel Tensor TPU & Camera HAL APEX firmware assets
                ;;
            *)
                unzip -o -q -d "$apk_dir" "$tmp_output/$split_apk" "assets/*" 2>/dev/null || true
                if [ -d "$apk_dir/assets" ]; then
                    mkdir -p "$base_src/assets"
                    cp -a "$apk_dir/assets/"* "$base_src/assets/"
                    info "Merged split assets/: ${split_apk}"
                fi
                ;;
        esac
    done

    # 2b. Prune unused Pixel TPU / HAL APEX assets and sync remaining uncompressed assets in apktool.yml
    prune_unused_assets "$base_src"
    if [ -d "$base_src/assets" ] && [ -f "$base_src/apktool.yml" ]; then
        local uncomp_assets
        uncomp_assets=$(cd "$base_src" && find assets -type f \( -name "*uncompressed*" -o -name "*.tflite" \) 2>/dev/null || true)
        if [ -n "$uncomp_assets" ] && grep -q "^doNotCompress:" "$base_src/apktool.yml"; then
            while IFS= read -r asset_rel; do
                [ -z "$asset_rel" ] && continue
                if ! grep -Fq "$asset_rel" "$base_src/apktool.yml"; then
                    ASSET_REL="$asset_rel" perl -0777 -pi -e 's/\ndoNotCompress:\n/\ndoNotCompress:\n- $ENV{ASSET_REL}\n/' "$base_src/apktool.yml"
                fi
            done <<< "$uncomp_assets"
        fi
    fi

    # 3. Strip split restrictions from AndroidManifest.xml
    local manifest_path="$base_src/AndroidManifest.xml"
    if [ -f "$manifest_path" ]; then
        sed_inplace -e 's/android:requiredSplitTypes="[^"]*"//g' "$manifest_path"
        sed_inplace -e 's/android:splitTypes="[^"]*"//g' "$manifest_path"
        sed_inplace -e 's/android:isSplitRequired="[^"]*"//g' "$manifest_path"
        sed_inplace -e 's/android:extractNativeLibs="false"/android:extractNativeLibs="true"/g' "$manifest_path"
        sed_inplace -e '/com\.android\.vending\.splits/d' "$manifest_path"
    fi

    # 4. Bypass Google Play Integrity / PairIP LicenseCheck if present
    local pairip_client
    pairip_client=$(find "$base_src" -name "LicenseClient.smali" 2>/dev/null | head -n 1 || true)
    if [ -n "$pairip_client" ]; then
        info "Bypassing PairIP license check..."
        perl -0777 -pi -e 's/\.method public static checkLicense\(Landroid\/content\/Context;\)V[\s\S]*?\.end method/.method public static checkLicense(Landroid\/content\/Context;)V\n    .locals 0\n    return-void\n.end method/g' "$pairip_client"

        local pairip_app
        pairip_app=$(find "$base_src" -path "*/com/pairip/application/Application.smali" 2>/dev/null | head -n 1 || true)
        if [ -n "$pairip_app" ]; then
            sed_inplace -e '/invoke-static.*checkLicense/d' "$pairip_app"
        fi

        local pairip_act
        pairip_act=$(find "$base_src" -name "LicenseActivity.smali" 2>/dev/null | head -n 1 || true)
        if [ -n "$pairip_act" ]; then
            perl -0777 -pi -e 's/\.method protected exitApp\(\)V[\s\S]*?\.end method/.method protected exitApp()V\n    .locals 0\n    return-void\n.end method/g' "$pairip_act"
            perl -0777 -pi -e 's/\.method private closeApp\(\)V[\s\S]*?\.end method/.method private closeApp()V\n    .locals 0\n    return-void\n.end method/g' "$pairip_act"
            perl -0777 -pi -e 's/\.method public onStart\(\)V[\s\S]*?\.end method/.method public onStart()V\n    .locals 0\n    invoke-super {p0}, Landroid\/app\/Activity;->onStart()V\n    invoke-virtual {p0}, Lcom\/pairip\/licensecheck\/LicenseActivity;->finish()V\n    return-void\n.end method/g' "$pairip_act"
        fi
    fi

    # 5. Rebuild unsigned APK
    local unsigned_apk="$tmp_output/unsigned.apk"
    $APKTOOL_CMD b -f -o "$unsigned_apk" "$base_src"

    # 6. Zipalign (-p for page-aligned uncompressed .so libraries)
    local aligned_apk="$tmp_output/aligned.apk"
    if command -v "$ZIPALIGN" &>/dev/null || [ -x "$ZIPALIGN" ]; then
        "$ZIPALIGN" -p -f 4 "$unsigned_apk" "$aligned_apk"
    else
        cp "$unsigned_apk" "$aligned_apk"
    fi

    # 7. Sign APK
    ensure_keystore
    $APKSIGNER_CMD sign \
        --ks "$APKX_KEYSTORE" \
        --ks-key-alias "$APKX_KEY_ALIAS" \
        --ks-pass "$APKX_KS_PASS" \
        --key-pass "$APKX_KEY_PASS" \
        --out "$target_apk" \
        "$aligned_apk"

    if [ -n "$keep_smali_dir" ]; then
        rm -rf "$base_src/build" "$keep_smali_dir"
        mkdir -p "$(dirname "$keep_smali_dir")"
        mv "$base_src" "$keep_smali_dir"
        ok "Saved merged smali directory -> ${GREEN}${keep_smali_dir}${NC}"
    fi

    rm -rf "${target_apk}.idsig" "$tmp_output"
    ok "Converted successfully -> ${GREEN}${target_apk}${NC}"
}
