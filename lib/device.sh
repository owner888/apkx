#!/usr/bin/env bash
# ============================================================================
# apkx — Device Management, Install/Launch, Logcat/Crash Stream, WiFi & Screen
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

check_device() {
    if ! command -v "$ADB" &>/dev/null && [ ! -x "$ADB" ]; then
        fail "adb not found. Please install Android SDK Platform-Tools."
    fi

    local devices
    devices=$("$ADB" devices | grep -w "device" | grep -v "List" | head -n 1 || true)
    if [ -z "$devices" ]; then
        fail "No Android device detected. Please verify:
  1. USB cable is connected (or paired via WiFi: apkx wifi)
  2. USB Debugging is enabled in Developer Options
  3. This computer is authorized on the phone"
    fi

    local serial
    serial=$(echo "$devices" | awk '{print $1}')
    ok "Device connected: ${CYAN}${serial}${NC}"
}

get_app_pid() {
    local pkg="$1"
    [ -z "$pkg" ] && return 0
    local pid=""
    local _i
    for _i in 1 2 3 4 5; do
        pid=$("$ADB" shell pidof -s "$pkg" 2>/dev/null | tr -d '\r' || true)
        if [ -n "$pid" ]; then
            echo "$pid"
            return 0
        fi
        sleep 0.3
    done
    echo ""
}

# Install & launch APK (compatible with legacy `apktool r` and `run.sh -r`)
cmd_run() {
    local clear_flag="${1:-}"
    check_device

    if [ -n "${APK_FILE:-}" ] && [ -d "$APK_FILE" ]; then
        cd "$APK_FILE"
    fi

    local apk_file_name
    apk_file_name=$(resolve_apk_file)

    if [ ! -f "$apk_file_name" ]; then
        fail "APK file not found: ${apk_file_name}"
    fi

    info "Installing ${apk_file_name} ..."
    if "$ADB" install --no-incremental -r -t -d "$apk_file_name" 2>&1 | grep -q "Success"; then
        ok "Installed successfully"
    else
        warn "Incremental/replace install failed, attempting clean reinstall..."
        local pkg_tmp
        pkg_tmp=$(resolve_package_name "$apk_file_name")
        [ -n "$pkg_tmp" ] && "$ADB" uninstall "$pkg_tmp" 2>/dev/null || true
        "$ADB" install --no-incremental -t "$apk_file_name" || fail "APK installation failed"
        ok "Reinstalled successfully"
    fi

    local pkg_name
    pkg_name=$(resolve_package_name "$apk_file_name")
    if [ -z "$pkg_name" ]; then
        warn "Could not resolve package name from ${apk_file_name}"
        return 0
    fi

    if [ "$clear_flag" = "clear" ]; then
        info "Clearing app data for ${pkg_name}..."
        "$ADB" shell pm clear "$pkg_name"
    fi

    local resolve_activity
    resolve_activity=$("$ADB" shell cmd package resolve-activity --brief "$pkg_name" 2>/dev/null | tr -d '\r' | tail -n 1 | grep -v '^$' || true)

    if [ -n "$resolve_activity" ] && [[ "$resolve_activity" == *"/"* ]]; then
        info "Launching ${CYAN}${resolve_activity}${NC} ..."
        "$ADB" shell am start -n "$resolve_activity"
    else
        info "Launching ${CYAN}${pkg_name}${NC} via monkey..."
        "$ADB" shell monkey -p "$pkg_name" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    fi
    ok "App launched"
}

# Combined Build + Run workflows
cmd_build_run() {
    cmd_plugin
    cmd_build
    cmd_run
}

cmd_build_run_logcat() {
    cmd_plugin
    cmd_build
    cmd_run
    cmd_logcat
}

cmd_build_run_logcat_clear() {
    cmd_plugin
    cmd_build
    cmd_run "clear"
    cmd_logcat
}

cmd_native_build_run_logcat() {
    cmd_native
    cmd_plugin
    cmd_build
    cmd_run
    cmd_logcat
}

cmd_run_logcat() {
    cmd_run
    cmd_logcat
}

# Stream Logcat (supports tag filtering or PID filtering)
cmd_logcat() {
    local mode="${1:-tags}"
    check_device

    if [ -n "${APK_FILE:-}" ] && [ -d "$APK_FILE" ]; then
        cd "$APK_FILE"
    fi

    local apk_file_name
    apk_file_name=$(resolve_apk_file)
    local pkg_name
    pkg_name=$(resolve_package_name "$apk_file_name")

    "$ADB" logcat -c 2>/dev/null || true

    if [ "$mode" = "pid" ] || [ "$mode" = "debug" ]; then
        local pid
        pid=$(get_app_pid "$pkg_name")
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  📱 PID Logcat — ${pkg_name:-unknown} (PID: ${pid:-waiting})${NC}"
        echo -e "${CYAN}  Press Ctrl+C to stop${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        if [ -n "$pid" ]; then
            "$ADB" logcat -v color --pid="$pid"
        else
            warn "Process ${pkg_name} not running; falling back to tag filter"
            # shellcheck disable=SC2086
            "$ADB" logcat -v color ${APKX_LOG_TAGS:--s AndroidRuntime -s DEBUG -s GoLog -s Go}
        fi
    else
        local log_tags="${APKX_LOG_TAGS:--s AndroidRuntime -s DEBUG -s GoLog -s Go}"
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${CYAN}  📱 Logcat Stream (${log_tags})${NC}"
        echo -e "${CYAN}  Press Ctrl+C to stop${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        # shellcheck disable=SC2086
        "$ADB" logcat -v color $log_tags
    fi
}

cmd_debug() {
    cmd_logcat "pid"
}

# Crash & Fatal Error Monitor
cmd_crash() {
    check_device
    local pkg_name
    pkg_name=$(resolve_package_name)
    local pid
    pid=$(get_app_pid "$pkg_name")

    echo ""
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}  💥 Crash Monitor ${pkg_name:+— $pkg_name }${pid:+(PID: $pid)}${NC}"
    echo -e "${RED}  Filtering: crash buffer / AndroidRuntime / FATAL / ANR${NC}"
    echo -e "${RED}  Press Ctrl+C to stop${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    "$ADB" logcat -c 2>/dev/null || true

    if [ "${1:-}" = "--raw" ]; then
        "$ADB" logcat -b crash
        return 0
    fi

    if [ -n "$pid" ]; then
        "$ADB" logcat -b crash -b main --pid="$pid" -v threadtime 2>/dev/null | \
            grep --line-buffered -iE "AndroidRuntime|FATAL|Exception|Error|ANR|crash|backtrace" | \
            while IFS= read -r line; do
                if echo "$line" | grep -qiE "FATAL|AndroidRuntime|ANR|crash|backtrace"; then
                    echo -e "${RED}${BOLD}$line${NC}"
                elif echo "$line" | grep -qi "Exception"; then
                    echo -e "${RED}$line${NC}"
                else
                    echo -e "${YELLOW}$line${NC}"
                fi
            done
    else
        "$ADB" logcat -b crash -v color
    fi
}

# Clear App Data
cmd_clear() {
    check_device
    local pkg="${1:-$(resolve_package_name)}"
    [ -z "$pkg" ] && fail "Could not determine package name. Usage: apkx clear <package.name>"
    info "Clearing data for ${CYAN}${pkg}${NC} ..."
    "$ADB" shell pm clear "$pkg"
    ok "Cleared app data for ${pkg}"
}

# Uninstall App
cmd_uninstall() {
    check_device
    local pkg="${1:-$(resolve_package_name)}"
    [ -z "$pkg" ] && fail "Could not determine package name. Usage: apkx uninstall <package.name>"
    info "Uninstalling ${CYAN}${pkg}${NC} ..."
    if "$ADB" uninstall "$pkg" 2>&1; then
        ok "Uninstalled ${pkg}"
    else
        warn "Package ${pkg} is not installed"
    fi
}

# Detailed Connected Devices & Hardware Card
cmd_device_info() {
    check_device
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━ Connected Devices ━━━━━━━━━━━━━━━━━━━${NC}"
    "$ADB" devices -l | grep -v "^List of devices" | grep -v "^$" | sed 's/^/  /'
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━ Device Information ━━━━━━━━━━━━━━━━━━━${NC}"

    local serial brand model android_ver sdk abi screen density ip storage battery
    serial=$("$ADB" get-serialno 2>/dev/null | tr -d '\r' || echo "unknown")
    brand=$("$ADB" shell getprop ro.product.brand 2>/dev/null | tr -d '\r')
    model=$("$ADB" shell getprop ro.product.model 2>/dev/null | tr -d '\r')
    android_ver=$("$ADB" shell getprop ro.build.version.release 2>/dev/null | tr -d '\r')
    sdk=$("$ADB" shell getprop ro.build.version.sdk 2>/dev/null | tr -d '\r')
    abi=$("$ADB" shell getprop ro.product.cpu.abi 2>/dev/null | tr -d '\r')
    screen=$("$ADB" shell wm size 2>/dev/null | awk '{print $NF}' | tr -d '\r')
    density=$("$ADB" shell wm density 2>/dev/null | awk '{print $NF}' | tr -d '\r')
    ip=$(detect_device_ip)
    storage=$("$ADB" shell df -h /data 2>/dev/null | tail -n 1 | awk '{printf "%s / %s (Used %s)", $3, $2, $5}' || true)
    battery=$("$ADB" shell dumpsys battery 2>/dev/null | grep "level:" | awk '{print $2}' | tr -d '\r' || true)

    echo -e "  ${BOLD}Serial:${NC}       ${serial}"
    echo -e "  ${BOLD}Device:${NC}       ${brand} ${model}"
    echo -e "  ${BOLD}Android:${NC}      ${android_ver} (API ${sdk})"
    echo -e "  ${BOLD}CPU ABI:${NC}      ${abi}"
    echo -e "  ${BOLD}Display:${NC}      ${screen} @ ${density}dpi"
    [ -n "$ip" ]      && echo -e "  ${BOLD}WLAN IP:${NC}      ${ip}"
    [ -n "$storage" ] && echo -e "  ${BOLD}Storage:${NC}      ${storage}"
    [ -n "$battery" ] && echo -e "  ${BOLD}Battery:${NC}      ${battery}%"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Multi-fallback device IP detection (ip route -> ip address -> ifconfig -> getprop)
detect_device_ip() {
    local ip=""
    # Method 1: ip route wlan0
    ip=$("$ADB" shell ip route 2>/dev/null | awk '/wlan0/ {print $9}' | head -n 1 | tr -d '\r' || true)
    # Method 2: ip address
    if [ -z "$ip" ]; then
        ip=$("$ADB" shell "ip address | grep 'inet ' | grep -v '127.0.0.1'" 2>/dev/null | head -n 1 | awk '{print $2}' | cut -d'/' -f1 | tr -d '\r' || true)
    fi
    # Method 3: ifconfig
    if [ -z "$ip" ]; then
        ip=$("$ADB" shell "ifconfig | grep 'inet ' | grep -v '127.0.0.1'" 2>/dev/null | head -n 1 | awk '{print $2}' | sed 's/addr://' | tr -d '\r' || true)
    fi
    # Method 4: dhcp.wlan0.ipaddress property
    if [ -z "$ip" ]; then
        ip=$("$ADB" shell getprop dhcp.wlan0.ipaddress 2>/dev/null | head -n 1 | tr -d '\r' || true)
    fi
    echo "$ip"
}

# Switch ADB to WiFi debugging (combines adbwifi + run.sh --wifi)
cmd_wifi() {
    local port="${1:-5555}"
    info "Switching ADB to WiFi mode (port ${port})..."
    check_device

    local ip
    ip=$(detect_device_ip)
    if [ -z "$ip" ]; then
        warn "Could not auto-detect device WLAN IP."
        echo -n "Enter device IP address manually: "
        read -r ip
    fi
    [ -z "$ip" ] && fail "No IP address provided"

    info "Device IP: ${CYAN}${ip}:${port}${NC}"
    "$ADB" tcpip "$port"
    sleep 1.5

    if "$ADB" connect "${ip}:${port}" 2>&1 | grep -q "connected"; then
        ok "Connected via WiFi: ${GREEN}${ip}:${port}${NC} (safe to unplug USB cable)"
        echo -e "  ${DIM}Switch back to USB: apkx usb${NC}"
    else
        fail "Failed to connect to ${ip}:${port}. Check that Mac and phone are on the same LAN."
    fi
}

# Switch ADB back to USB mode
cmd_usb() {
    info "Switching ADB back to USB mode..."
    local wifi_devs
    wifi_devs=$("$ADB" devices | grep -E "^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:" | awk '{print $1}' || true)
    if [ -n "$wifi_devs" ]; then
        echo "$wifi_devs" | while IFS= read -r dev; do
            info "Disconnecting WiFi device: ${dev}"
            "$ADB" disconnect "$dev" 2>/dev/null || true
        done
    fi
    "$ADB" usb 2>/dev/null || true
    sleep 1
    check_device
}

# Capture Device Screenshot
cmd_screen() {
    check_device
    local dir="screenshots"
    mkdir -p "$dir"
    local filename="${dir}/screen_$(date '+%Y-%m-%d_%H-%M-%S').png"

    info "Capturing device screenshot..."
    "$ADB" exec-out screencap -p > "$filename" 2>/dev/null

    if [ -s "$filename" ]; then
        local fsize
        fsize=$(du -h "$filename" | awk '{print $1}')
        ok "Saved screenshot: ${CYAN}${filename}${NC} (${fsize})"
        if [[ "$OSTYPE" == "darwin"* ]] && command -v open &>/dev/null; then
            open "$filename"
        fi
    else
        rm -f "$filename"
        fail "Failed to capture screenshot"
    fi
}
# List installed packages on the connected Android device
# Usage:
#   apkx packages [keyword]          -> list 3rd-party packages (filtered by keyword if given)
#   apkx packages --all [keyword]    -> list all packages (including system packages)
cmd_packages() {
    check_device
    local flag="-3"
    local keyword=""

    for arg in "$@"; do
        case "$arg" in
            --all|-a) flag="" ;;
            *) keyword="$arg" ;;
        esac
    done

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━ Installed Packages ${flag:+(3rd-Party) }━━━━━━━━━━━━━━━━━━━${NC}"

    local pkgs
    # shellcheck disable=SC2086
    pkgs=$("$ADB" shell pm list packages $flag 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort || true)
    if [ -n "$keyword" ]; then
        pkgs=$(echo "$pkgs" | grep -i "$keyword" || true)
    fi

    if [ -z "$pkgs" ] && [ "$flag" = "-3" ] && [ -n "$keyword" ]; then
        info "No 3rd-party package matched '${keyword}', searching system packages..."
        pkgs=$("$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort | grep -i "$keyword" || true)
    fi

    if [ -z "$pkgs" ]; then
        warn "No packages found${keyword:+ matching '$keyword'}"
        echo ""
        return 0
    fi

    local count=0
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        count=$(( count + 1 ))
        printf "  ${GREEN}%3d.${NC} %s\n" "$count" "$pkg"
    done <<< "$pkgs"

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  Total: ${BOLD}${count}${NC} package(s)  ${DIM}(Tip: run 'apkx pull <package>' to extract APK)${NC}"
    echo ""
}

# Pull an installed app's APK(s) from the device; automatically merges split APKs into a standalone APK
cmd_pull() {
    local query="${1:-${APK_FILE:-}}"
    [ -z "$query" ] && fail "Usage: apkx pull <package-name-or-keyword> [--raw]"
    local raw_mode="${2:-}"
    check_device

    # Resolve package name (exact match first, then substring match in 3rd-party, then all packages)
    local all_pkgs matched_pkg=""
    all_pkgs=$("$ADB" shell pm list packages 2>/dev/null | tr -d '\r' | sed 's/^package://' | sort || true)

    if echo "$all_pkgs" | grep -Fxq "$query"; then
        matched_pkg="$query"
    else
        local candidates
        candidates=$("$ADB" shell pm list packages -3 2>/dev/null | tr -d '\r' | sed 's/^package://' | grep -i "$query" || true)
        if [ -z "$candidates" ]; then
            candidates=$(echo "$all_pkgs" | grep -i "$query" || true)
        fi
        local cand_count
        cand_count=$(echo "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')
        if [ "$cand_count" -eq 0 ]; then
            fail "No installed package found matching '${query}'"
        elif [ "$cand_count" -gt 1 ]; then
            warn "Multiple packages matched '${query}':"
            echo "$candidates" | sed 's/^/  - /'
            fail "Please specify a more exact package name."
        fi
        matched_pkg=$(echo "$candidates" | head -n 1)
    fi

    info "Inspecting APK paths for ${CYAN}${matched_pkg}${NC} ..."
    local apk_paths
    apk_paths=$("$ADB" shell pm path "$matched_pkg" 2>/dev/null | tr -d '\r' | sed 's/^package://' || true)
    [ -z "$apk_paths" ] && fail "Could not retrieve APK path for ${matched_pkg}"

    local path_count
    path_count=$(echo "$apk_paths" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$path_count" -eq 1 ]; then
        local remote_path
        remote_path=$(echo "$apk_paths" | head -n 1)
        local out_apk="${matched_pkg}.apk"
        info "Pulling single APK -> ${GREEN}${out_apk}${NC} ..."
        "$ADB" pull "$remote_path" "$out_apk"
        local sz
        sz=$(du -h "$out_apk" | awk '{print $1}')
        ok "Pulled ${GREEN}${out_apk}${NC} (${sz})"
    else
        info "Detected ${YELLOW}${path_count}${NC} split APKs for ${CYAN}${matched_pkg}${NC}..."
        local tmp_pull_dir="${TMPDIR:-/tmp/}apkx_pull_${matched_pkg}_$$"
        rm -rf "$tmp_pull_dir"
        mkdir -p "$tmp_pull_dir"

        while IFS= read -r rpath; do
            [ -z "$rpath" ] && continue
            local bname
            bname=$(basename "$rpath")
            info "Pulling ${bname} ..."
            "$ADB" pull "$rpath" "$tmp_pull_dir/$bname" >/dev/null
        done <<< "$apk_paths"

        local bundle_apkm="${matched_pkg}.apkm"
        (cd "$tmp_pull_dir" && zip -0 -q "$OLDPWD/$bundle_apkm" ./*.apk)
        rm -rf "$tmp_pull_dir"

        if [ "$raw_mode" = "--raw" ]; then
            ok "Saved split bundle: ${GREEN}${bundle_apkm}${NC}"
        else
            info "Merging split bundle into standalone ${matched_pkg}.apk ..."
            cmd_convert "$bundle_apkm"
            rm -f "$bundle_apkm"
        fi
    fi
}
