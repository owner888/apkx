#!/usr/bin/env bash
# ============================================================================
# apkx — AI Agent Friendly Unattended Modes (build-only, smoke-test, log-dump)
# Copyright (c) 2026 Pig (https://pigagent.dev) & owner888
# Crafted by Pig Coding Agent (https://github.com/owner888/pig)
# ============================================================================

# Headless build check (no device required)
cmd_build_only() {
    info "Running headless build check (no device required)..."
    local start_time=$SECONDS
    local build_output=""
    local status=0

    build_output=$(cmd_build -d 2>&1) || status=$?
    local elapsed=$(( SECONDS - start_time ))
    local apk_file
    apk_file=$(resolve_apk_file)

    if [ "$status" -eq 0 ] && [ -f "$apk_file" ]; then
        local size
        size=$(du -h "$apk_file" 2>/dev/null | awk '{print $1}' || echo "?")
        echo "[BUILD] STATUS: OK"
        echo "[BUILD] APK: ${apk_file} (${size})"
        echo "[BUILD] TIME: ${elapsed}s"
        return 0
    else
        echo "[BUILD] STATUS: FAILED"
        echo "[BUILD] TIME: ${elapsed}s"
        echo "[BUILD] ERRORS:"
        echo "$build_output" | grep -iE "Exception|Error|FAILED|✖" | head -n 30
        return 1
    fi
}

# Automated Smoke Test: Build -> Install -> Launch -> Wait -> PID Check -> Crash Check -> Screenshot
cmd_smoke_test() {
    local wait_sec="${1:-8}"
    check_device

    local ts
    ts=$(date '+%Y-%m-%d_%H-%M-%S')
    local log_file="logs/test_${ts}.log"
    local screen_file="screenshots/test_${ts}.png"
    mkdir -p logs screenshots

    local result="PASS"
    echo "[TEST] === apkx Automated Smoke Test ==="
    echo "[TEST] TIMESTAMP: ${ts}"

    # 1. Build
    local start_time=$SECONDS
    local build_output=""
    local status=0
    build_output=$(cmd_build -d 2>&1) || status=$?
    local build_time=$(( SECONDS - start_time ))
    local apk_file
    apk_file=$(resolve_apk_file)

    if [ "$status" -eq 0 ] && [ -f "$apk_file" ]; then
        local size
        size=$(du -h "$apk_file" | awk '{print $1}')
        echo "[TEST] BUILD: OK (${size}, ${build_time}s)"
    else
        echo "[TEST] BUILD: FAILED (${build_time}s)"
        echo "$build_output" > "$log_file"
        echo "[TEST] BUILD_LOG: ${log_file}"
        echo "[TEST] RESULT: FAIL"
        return 1
    fi

    # 2. Install & Launch
    "$ADB" logcat -c 2>/dev/null || true
    if cmd_run >/dev/null 2>&1; then
        echo "[TEST] INSTALL_AND_LAUNCH: OK"
    else
        echo "[TEST] INSTALL_AND_LAUNCH: FAILED"
        echo "[TEST] RESULT: FAIL"
        return 1
    fi

    local pkg_name
    pkg_name=$(resolve_package_name "$apk_file")
    echo "[TEST] PACKAGE: ${pkg_name:-unknown}"

    # 3. Wait
    echo "[TEST] WAITING: ${wait_sec}s..."
    sleep "$wait_sec"

    # 4. Alive check
    local pid=""
    if [ -n "$pkg_name" ]; then
        pid=$("$ADB" shell pidof -s "$pkg_name" 2>/dev/null | tr -d '\r' || true)
    fi
    if [ -n "$pid" ]; then
        echo "[TEST] ALIVE_CHECK: OK (PID: ${pid})"
    else
        echo "[TEST] ALIVE_CHECK: FAIL (process exited within ${wait_sec}s)"
        result="FAIL"
    fi

    # 5. Capture logs
    if [ -n "$pid" ]; then
        "$ADB" logcat -d --pid="$pid" -v threadtime > "$log_file" 2>/dev/null || \
            "$ADB" logcat -d -v threadtime > "$log_file" 2>/dev/null || true
    else
        "$ADB" logcat -d -v threadtime > "$log_file" 2>/dev/null || true
    fi
    local log_lines
    log_lines=$(wc -l < "$log_file" | tr -d ' ')
    echo "[TEST] LOGCAT: ${log_file} (${log_lines} lines)"

    # 6. Crash check
    local crash_lines
    crash_lines=$({ grep -iE "FATAL EXCEPTION|AndroidRuntime.*FATAL|ANR in ${pkg_name:-app}" "$log_file" || true; } | head -n 10)
    if [ -n "$crash_lines" ]; then
        echo "[TEST] CRASH: DETECTED"
        echo "$crash_lines" | while IFS= read -r line; do
            echo "[TEST] CRASH_LOG: $line"
        done
        result="FAIL"
    else
        echo "[TEST] CRASH: NONE"
    fi

    # 7. Screenshot
    "$ADB" exec-out screencap -p > "$screen_file" 2>/dev/null || true
    if [ -s "$screen_file" ]; then
        echo "[TEST] SCREENSHOT: ${screen_file}"
    else
        rm -f "$screen_file"
        echo "[TEST] SCREENSHOT: FAILED"
    fi

    echo "[TEST] RESULT: ${result}"
    [ "$result" = "PASS" ] && return 0 || return 1
}

# Bounded N-second Logcat Dump to file (never hangs)
cmd_logcat_dump() {
    local sec="${1:-10}"
    check_device

    local ts
    ts=$(date '+%Y-%m-%d_%H-%M-%S')
    local log_file="logs/logcat_${ts}.log"
    mkdir -p logs

    local pkg_name pid
    pkg_name=$(resolve_package_name)
    pid=$(get_app_pid "$pkg_name")

    "$ADB" logcat -c 2>/dev/null || true
    echo "[LOGCAT_DUMP] Capturing ${sec}s of logs..."

    if [ -n "$pid" ]; then
        "$ADB" logcat --pid="$pid" -v threadtime > "$log_file" 2>/dev/null &
    else
        "$ADB" logcat -v threadtime > "$log_file" 2>/dev/null &
    fi
    local adb_pid=$!
    sleep "$sec"
    kill "$adb_pid" 2>/dev/null || true
    wait "$adb_pid" 2>/dev/null || true

    local lines errors
    lines=$(wc -l < "$log_file" | tr -d ' ')
    errors=$({ grep -ciE "AndroidRuntime|FATAL|Exception" "$log_file" || true; })

    echo "[LOGCAT_DUMP] FILE: ${log_file} (${lines} lines, ${sec}s)"
    echo "[LOGCAT_DUMP] ERRORS: ${errors}"
    return 0
}
