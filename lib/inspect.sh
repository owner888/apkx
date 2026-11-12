#!/usr/bin/env bash
# ============================================================================
# apkx — APK Inspection, Package Metadata, Size Breakdown & Version Info
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

cmd_pkginfo() {
    cmd_size "${1:-}"
}

cmd_size() {
    local target="${1:-$(resolve_apk_file)}"
    if [ ! -f "$target" ]; then
        warn "APK not found (${target}); building first..."
        cmd_build -d
        target=$(resolve_apk_file)
    fi
    [ ! -f "$target" ] && fail "APK file not found: ${target}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━ APK Info & Size Analysis ━━━━━━━━━━━━━━━━━━${NC}"

    local total_size
    total_size=$(du -h "$target" | awk '{print $1}')
    echo -e "  ${BOLD}File:${NC}        ${target}"
    echo -e "  ${BOLD}Total Size:${NC}  ${GREEN}${total_size}${NC}"

    if [ -x "$AAPT" ] || command -v "$AAPT" &>/dev/null; then
        local badging pkg_info pkg_name pkg_ver pkg_code min_sdk target_sdk launch_act
        badging=$("$AAPT" dump badging "$target" 2>/dev/null || true)
        pkg_info=$(echo "$badging" | head -n 1)
        pkg_name=$(echo "$pkg_info" | grep -oE "name='[^']+'" | head -n 1 | cut -d"'" -f2 || true)
        pkg_ver=$(echo "$pkg_info" | grep -oE "versionName='[^']+'" | head -n 1 | cut -d"'" -f2 || true)
        pkg_code=$(echo "$pkg_info" | grep -oE "versionCode='[^']+'" | head -n 1 | cut -d"'" -f2 || true)
        min_sdk=$(echo "$badging" | grep -m1 "^sdkVersion:" | cut -d"'" -f2 || true)
        target_sdk=$(echo "$badging" | grep -m1 "^targetSdkVersion:" | cut -d"'" -f2 || true)
        launch_act=$(echo "$badging" | grep -m1 "^launchable-activity:" | grep -oE "name='[^']+'" | head -n 1 | cut -d"'" -f2 || true)

        [ -n "$pkg_name" ]   && echo -e "  ${BOLD}Package:${NC}     ${CYAN}${pkg_name}${NC}"
        [ -n "$pkg_ver" ]    && echo -e "  ${BOLD}Version:${NC}     ${pkg_ver} (code: ${pkg_code:-?})"
        [ -n "$min_sdk" ]    && echo -e "  ${BOLD}SDK:${NC}         minSdk=${min_sdk} / targetSdk=${target_sdk:-?}"
        [ -n "$launch_act" ] && echo -e "  ${BOLD}Activity:${NC}    ${launch_act}"
    fi

    echo ""
    echo -e "  ${BOLD}Component Breakdown (Uncompressed):${NC}"
    local apk_list
    apk_list=$(unzip -l "$target" 2>/dev/null || true)

    local dex_size lib_size res_size assets_size
    dex_size=$(echo "$apk_list" | { grep "\.dex$" || true; } | awk '{sum+=$1} END {if(sum>0) printf "%.2f MB", sum/1024/1024; else print "0 KB"}')
    lib_size=$(echo "$apk_list" | { grep "lib/" || true; } | awk '{sum+=$1} END {if(sum>0) printf "%.2f MB", sum/1024/1024; else print "0 KB"}')
    res_size=$(echo "$apk_list" | { grep "res/" || true; } | awk '{sum+=$1} END {if(sum>0) printf "%.2f MB", sum/1024/1024; else print "0 KB"}')
    assets_size=$(echo "$apk_list" | { grep "assets/" || true; } | awk '{sum+=$1} END {if(sum>0) printf "%.2f MB", sum/1024/1024; else print "0 KB"}')

    echo -e "    DEX (Bytecode):   ${dex_size}"
    echo -e "    lib/ (Native):    ${lib_size}"
    echo -e "    res/ (Resources): ${res_size}"
    echo -e "    assets/:          ${assets_size}"

    echo ""
    echo -e "  ${BOLD}Native Libraries (.so):${NC}"
    local so_list
    so_list=$(echo "$apk_list" | { grep "\.so$" || true; } | awk '{printf "    %-48s %8.1f KB\n", $4, $1/1024}' | sort)
    if [ -n "$so_list" ]; then
        echo "$so_list"
    else
        echo -e "    ${DIM}(no .so files bundled)${NC}"
    fi

    if [ -n "$ANDROID_BUILD_TOOLS" ] && [ -x "$ANDROID_BUILD_TOOLS/dexdump" ]; then
        echo ""
        local method_count dex_count
        method_count=$("$ANDROID_BUILD_TOOLS/dexdump" -f "$target" 2>/dev/null | { grep "method_ids_size" || true; } | awk '{sum+=$NF} END {print sum+0}')
        dex_count=$(echo "$apk_list" | grep -c "\.dex$" || true)
        echo -e "  ${BOLD}DEX Methods:${NC} ${method_count:-N/A} total across ${dex_count} DEX file(s)"
    fi

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

cmd_version() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━ apkx & Project Version ━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}apkx CLI:${NC}    v${APKX_VERSION}"

    local git_hash git_branch git_dirty
    git_hash=$(git rev-parse --short HEAD 2>/dev/null || echo "-")
    git_branch=$(git branch --show-current 2>/dev/null || echo "-")
    git_dirty=""
    if git rev-parse --git-dir >/dev/null 2>&1 && ! git diff --quiet 2>/dev/null; then
        git_dirty=" ${YELLOW}(dirty)${NC}"
    fi
    if [ "$git_hash" != "-" ]; then
        echo -e "  ${BOLD}Git:${NC}         ${git_branch} @ ${git_hash}${git_dirty}"
    fi

    if [ -n "$APKTOOL_YML" ] && [ -f "$APKTOOL_YML" ]; then
        local yml_ver
        yml_ver=$(grep -Eo "^ *versionName: *.*" "$APKTOOL_YML" 2>/dev/null | awk -F ': ' '{print $2}' | tr -d "'\"" || echo "-")
        echo -e "  ${BOLD}Project:${NC}     ${PROJ_DIR} (apktool.yml version: ${yml_ver})"
    fi

    read_version
    if [ -n "$VERSION" ]; then
        echo -e "  ${BOLD}Smali Ver:${NC}   ${VERSION}"
    fi

    local apk_file
    apk_file=$(resolve_apk_file)
    if [ -f "$apk_file" ]; then
        local sz
        sz=$(du -h "$apk_file" | awk '{print $1}')
        echo -e "  ${BOLD}Output APK:${NC}  ${apk_file} (${sz})"
    fi
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}