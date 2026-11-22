#!/bin/sh
# ============================================================================
# apkx installer — https://github.com/owner888/apkx
#
#   curl -fsSL https://raw.githubusercontent.com/owner888/apkx/main/install.sh | sh
#
# Like MyPHP's and Pig's installers:
#   - Checks required system dependencies (git, curl, unzip, perl, java/keytool,
#     adb, jadx, zipalign/aapt/d8) BEFORE cloning, and automatically installs
#     missing ones according to the detected OS / package manager (Homebrew,
#     apt, dnf, pacman, apk, pkg/Termux).
#   - Clones or updates https://github.com/owner888/apkx into ~/.apkx (or $APKX_HOME).
#   - Initializes the publicized Android framework and debug.keystore via `apkx setup`.
#   - Links `apkx` into an existing writable directory on PATH for instant use,
#     and offers to add the bin directory to your shell profile if needed.
#
# Every function is defined before the last line calls one: a truncated download
# defines some functions and does nothing, instead of half an install.
# ============================================================================

APKX_REPO_URL="${APKX_REPO_URL:-https://github.com/owner888/apkx.git}"
APKX_BRANCH="${APKX_BRANCH:-main}"
APKX_HOME="${APKX_HOME:-$HOME/.apkx}"
APKX_CMD="apkx"
readonly APKX_REPO_URL APKX_BRANCH APKX_CMD

INITIAL_PATH="${PATH:-}"

apkx_installer_main() {
  set -eu

  INITIAL_PATH="${PATH:-}"

  printf '\n  \033[1mapkx\033[0m \033[2m— Android APK Reverse Engineering, Repackaging & Debug CLI\033[0m\n\n'

  if ! check_and_install_dependencies; then
    printf '\nNothing was installed.\n'
    exit 1
  fi

  install_or_update_apkx_repo

  bin_dir="$APKX_HOME/bin"
  apkx_bin="$bin_dir/$APKX_CMD"
  chmod +x "$apkx_bin" 2>/dev/null || true

  # Initialize publicized Android framework (1.apk) & local debug.keystore
  initialize_apkx_toolchain "$apkx_bin"

  # Try linking apkx into an existing directory on PATH for instant availability
  link_apkx_to_path "$bin_dir" || true

  # Ensure the directory is permanently added to the user's shell profile if not already on PATH
  if ! installed_apkx_is_first_on_path "$bin_dir"; then
    config_file=$(shell_config_file)
    if ! config_file_mentions_path "$config_file" "$bin_dir"; then
      prompt_add_path_to_profile "$bin_dir" "$APKX_CMD" || true
    fi
  fi

  if installed_apkx_is_first_on_path "$bin_dir"; then
    printf '\n  \033[0;32m✔\033[0m apkx is installed and ready! Run it with: \033[1m%s\033[0m\n' "$APKX_CMD"
  else
    print_not_on_path_message "$bin_dir"
  fi

  printf '\n  Diagnose environment:  \033[0;36mapkx doctor\033[0m\n'
  printf '  Show all commands:     \033[0;36mapkx --help\033[0m\n'
  printf '  Update apkx anytime:   \033[0;36mapkx upgrade\033[0m\n\n'
}

# ---- dependency detection & automatic per-OS installation -------------------------------

is_termux() {
  [ -n "${TERMUX_VERSION:-}" ] && return 0
  [ -d "/data/data/com.termux" ] && return 0
  case "${PREFIX:-}" in *com.termux*) return 0 ;; esac
  return 1
}

detect_pkg_manager() {
  if is_termux && command -v pkg >/dev/null 2>&1; then
    printf 'termux'
    return 0
  fi

  os=$(uname -s 2>/dev/null || echo "Unknown")
  case "$os" in
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        printf 'brew'
        return 0
      fi
      ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        printf 'apt'
        return 0
      elif command -v dnf >/dev/null 2>&1; then
        printf 'dnf'
        return 0
      elif command -v pacman >/dev/null 2>&1; then
        printf 'pacman'
        return 0
      elif command -v apk >/dev/null 2>&1; then
        printf 'apk'
        return 0
      elif command -v brew >/dev/null 2>&1; then
        printf 'brew'
        return 0
      fi
      ;;
  esac

  printf 'unknown'
}

run_as_root() {
  if [ "$(id -u 2>/dev/null || echo 1)" -eq 0 ]; then
    "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo "$@"
  else
    return 1
  fi
}

java_major_version() {
  command -v java >/dev/null 2>&1 || return 1
  ver_line=$(java -version 2>&1 | head -n 1 || true)
  ver=$(printf '%s' "$ver_line" | sed -n 's/.*version "\([^"]*\)".*/\1/p')
  if [ -z "$ver" ]; then
    ver=$(printf '%s' "$ver_line" | awk '{print $3}' | tr -d '"')
  fi
  case "$ver" in
    1.*) major=$(printf '%s' "$ver" | cut -d'.' -f2) ;;
    *)   major=$(printf '%s' "$ver" | cut -d'.' -f1 | sed 's/[^0-9].*//') ;;
  esac
  [ -n "$major" ] && printf '%s' "$major" && return 0
  return 1
}

has_valid_java() {
  major=$(java_major_version 2>/dev/null || true)
  [ -n "$major" ] && [ "$major" -ge 11 ] 2>/dev/null
}

# Expose existing Android SDK platform-tools & build-tools on PATH before checking
augment_android_sdk_path() {
  sdk_root="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
  if [ -z "$sdk_root" ]; then
    for candidate in "$HOME/Library/Android/sdk" "$HOME/Android/Sdk" "/opt/android-sdk" "/usr/lib/android-sdk"; do
      if [ -d "$candidate" ]; then
        sdk_root="$candidate"
        break
      fi
    done
  fi

  if [ -n "$sdk_root" ] && [ -d "$sdk_root" ]; then
    if [ -d "$sdk_root/platform-tools" ]; then
      PATH="$sdk_root/platform-tools:$PATH"
    fi
    if [ -d "$sdk_root/build-tools" ]; then
      latest_bt=$(ls "$sdk_root/build-tools" 2>/dev/null | sort -V | tail -n 1 || true)
      if [ -n "$latest_bt" ] && [ -d "$sdk_root/build-tools/$latest_bt" ]; then
        PATH="$sdk_root/build-tools/$latest_bt:$PATH"
      fi
    fi
    export PATH
  fi

  for brew_prefix in /opt/homebrew /usr/local; do
    if [ -d "$brew_prefix/opt/openjdk/bin" ]; then
      case ":$PATH:" in
        *":$brew_prefix/opt/openjdk/bin:"*) ;;
        *) PATH="$brew_prefix/opt/openjdk/bin:$PATH"; export PATH ;;
      esac
    fi
  done
}

check_and_install_dependencies() {
  augment_android_sdk_path

  pkg_mgr=$(detect_pkg_manager)
  apt_updated=0

  printf '  \033[0;34m▸\033[0m Checking system environment & dependencies...\n'

  # 1. Core utilities: git, curl, unzip, zip, perl
  for tool in git curl unzip zip perl; do
    if command -v "$tool" >/dev/null 2>&1; then
      printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "$tool" "$(command -v "$tool")"
    else
      printf '    \033[1;33m⚠\033[0m %-16s missing — installing via %s...\n' "$tool" "$pkg_mgr"
      install_system_package "$pkg_mgr" "$tool" || true
      if command -v "$tool" >/dev/null 2>&1; then
        printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "$tool" "$(command -v "$tool")"
      else
        printf '    \033[0;31m✖\033[0m Required dependency "%s" could not be installed automatically.\n' "$tool"
        print_manual_install_hint "$tool"
        return 1
      fi
    fi
  done

  # 2. Java / JDK 11+ (required for apktool, apksigner, baksmali, smali, keytool)
  if has_valid_java && command -v keytool >/dev/null 2>&1; then
    printf '    \033[0;32m✔\033[0m %-16s \033[2mJDK %s (%s)\033[0m\n' "java" "$(java_major_version)" "$(command -v java)"
  else
    printf '    \033[1;33m⚠\033[0m %-16s missing or < 11 — installing OpenJDK...\n' "java (JDK 11+)"
    install_jdk_package "$pkg_mgr" || true
    augment_android_sdk_path
    if has_valid_java; then
      printf '    \033[0;32m✔\033[0m %-16s \033[2mJDK %s (%s)\033[0m\n' "java" "$(java_major_version)" "$(command -v java)"
    else
      printf '    \033[0;31m✖\033[0m Java (JDK 11+) is required to run apktool, smali, and apksigner.\n'
      print_manual_install_hint "openjdk"
      return 1
    fi
  fi

  # 3. Android & Reverse Engineering tools: adb, jadx, zipalign, aapt
  #    Automatically installed where available in the system package manager.
  if command -v adb >/dev/null 2>&1; then
    printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "adb" "$(command -v adb)"
  else
    printf '    \033[1;33m⚠\033[0m %-16s missing — attempting automatic install...\n' "adb"
    install_adb_package "$pkg_mgr" || true
    augment_android_sdk_path
    if command -v adb >/dev/null 2>&1; then
      printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "adb" "$(command -v adb)"
    else
      printf '    \033[1;33m⚠\033[0m %-16s \033[2mnot installed (optional for headless build/decode)\033[0m\n' "adb"
    fi
  fi

  if command -v jadx >/dev/null 2>&1; then
    printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "jadx" "$(command -v jadx)"
  else
    printf '    \033[1;33m⚠\033[0m %-16s missing — attempting automatic install...\n' "jadx"
    install_jadx_package "$pkg_mgr" || true
    if command -v jadx >/dev/null 2>&1; then
      printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "jadx" "$(command -v jadx)"
    else
      printf '    \033[1;33m⚠\033[0m %-16s \033[2mnot installed (install jadx for Java source decompilation)\033[0m\n' "jadx"
    fi
  fi

  for sdk_tool in zipalign aapt; do
    if command -v "$sdk_tool" >/dev/null 2>&1; then
      printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "$sdk_tool" "$(command -v "$sdk_tool")"
    else
      install_android_build_tool "$pkg_mgr" "$sdk_tool" || true
      augment_android_sdk_path
      if command -v "$sdk_tool" >/dev/null 2>&1; then
        printf '    \033[0;32m✔\033[0m %-16s \033[2m%s\033[0m\n' "$sdk_tool" "$(command -v "$sdk_tool")"
      else
        printf '    \033[1;33m⚠\033[0m %-16s \033[2mnot found on PATH (install Android SDK Build-Tools if needed)\033[0m\n' "$sdk_tool"
      fi
    fi
  done

  return 0
}

apt_update_once() {
  if [ "${apt_updated:-0}" -eq 0 ]; then
    run_as_root apt-get update -qq >/dev/null 2>&1 || true
    apt_updated=1
  fi
}

install_system_package() {
  mgr="$1"
  pkg="$2"
  case "$mgr" in
    brew)
      brew install "$pkg"
      ;;
    apt)
      apt_update_once
      DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y "$pkg"
      ;;
    dnf)
      run_as_root dnf install -y "$pkg"
      ;;
    pacman)
      run_as_root pacman -Sy --noconfirm "$pkg"
      ;;
    apk)
      run_as_root apk add --no-cache "$pkg"
      ;;
    termux)
      pkg install -y "$pkg"
      ;;
    *)
      return 1
      ;;
  esac
}

install_jdk_package() {
  mgr="$1"
  case "$mgr" in
    brew)
      brew install openjdk
      for brew_prefix in /opt/homebrew /usr/local; do
        if [ -d "$brew_prefix/opt/openjdk/bin" ]; then
          PATH="$brew_prefix/opt/openjdk/bin:$PATH"
          export PATH
        fi
      done
      ;;
    apt)
      apt_update_once
      DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y default-jdk || \
        DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y openjdk-17-jdk
      ;;
    dnf)
      run_as_root dnf install -y java-17-openjdk-devel || \
        run_as_root dnf install -y java-latest-openjdk-devel
      ;;
    pacman)
      run_as_root pacman -Sy --noconfirm jdk-openjdk
      ;;
    apk)
      run_as_root apk add --no-cache openjdk17-jdk || \
        run_as_root apk add --no-cache openjdk11-jdk
      ;;
    termux)
      pkg install -y openjdk-17
      ;;
    *)
      return 1
      ;;
  esac
}

install_adb_package() {
  mgr="$1"
  case "$mgr" in
    brew)
      brew install --cask android-platform-tools || brew install android-platform-tools
      ;;
    apt)
      apt_update_once
      DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y adb
      ;;
    dnf)
      run_as_root dnf install -y android-tools
      ;;
    pacman)
      run_as_root pacman -Sy --noconfirm android-tools
      ;;
    apk)
      run_as_root apk add --no-cache android-tools
      ;;
    termux)
      pkg install -y android-tools
      ;;
    *)
      return 1
      ;;
  esac
}

install_jadx_package() {
  mgr="$1"
  case "$mgr" in
    brew)
      brew install jadx
      ;;
    apt)
      apt_update_once
      if ! DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y jadx 2>/dev/null; then
        install_jadx_from_github_release
      fi
      ;;
    pacman)
      run_as_root pacman -Sy --noconfirm jadx || install_jadx_from_github_release
      ;;
    termux)
      pkg install -y jadx || install_jadx_from_github_release
      ;;
    *)
      install_jadx_from_github_release
      ;;
  esac
}

install_jadx_from_github_release() {
  jadx_ver="1.5.1"
  jadx_dir="$HOME/.apkx/jadx"
  jadx_zip="${TMPDIR:-/tmp}/jadx-${jadx_ver}.zip"
  jadx_url="https://github.com/skylot/jadx/releases/download/v${jadx_ver}/jadx-${jadx_ver}.zip"

  mkdir -p "$jadx_dir" "$HOME/.local/bin" 2>/dev/null || true
  if curl -fsSL "$jadx_url" -o "$jadx_zip" 2>/dev/null; then
    if unzip -o -q "$jadx_zip" -d "$jadx_dir" 2>/dev/null; then
      rm -f "$jadx_zip"
      chmod +x "$jadx_dir/bin/jadx" "$jadx_dir/bin/jadx-gui" 2>/dev/null || true
      link_binary_to_path "$jadx_dir/bin/jadx" "jadx" >/dev/null 2>&1 || \
        ln -sf "$jadx_dir/bin/jadx" "$HOME/.local/bin/jadx" 2>/dev/null || true
      link_binary_to_path "$jadx_dir/bin/jadx-gui" "jadx-gui" >/dev/null 2>&1 || \
        ln -sf "$jadx_dir/bin/jadx-gui" "$HOME/.local/bin/jadx-gui" 2>/dev/null || true
      PATH="$jadx_dir/bin:$HOME/.local/bin:$PATH"
      export PATH
      return 0
    fi
    rm -f "$jadx_zip"
  fi
  return 1
}

install_android_build_tool() {
  mgr="$1"
  tool="$2"
  case "$mgr" in
    apt)
      apt_update_once
      DEBIAN_FRONTEND=noninteractive run_as_root apt-get install -y "$tool" >/dev/null 2>&1
      ;;
    termux)
      pkg install -y "$tool" >/dev/null 2>&1 || pkg install -y aapt >/dev/null 2>&1
      ;;
    *)
      return 1
      ;;
  esac
}

print_manual_install_hint() {
  pkg="$1"
  os=$(uname -s 2>/dev/null || echo "Unknown")
  case "$os" in
    Darwin)
      printf '         On macOS, install Homebrew (https://brew.sh) and run: brew install %s\n' "$pkg"
      ;;
    Linux)
      printf '         On Linux, install "%s" using your package manager (apt, dnf, pacman, or apk).\n' "$pkg"
      ;;
    *)
      printf '         Please install "%s" and ensure it is on your PATH.\n' "$pkg"
      ;;
  esac
}

# ---- clone or update apkx repository from GitHub ----------------------------------------

install_or_update_apkx_repo() {
  if [ -d "$APKX_HOME/.git" ]; then
    printf '\n  \033[0;34m▸\033[0m Updating existing apkx installation in %s...\n' "$APKX_HOME"
    git -C "$APKX_HOME" fetch --depth 1 origin "$APKX_BRANCH"
    git -C "$APKX_HOME" reset --hard "origin/$APKX_BRANCH" >/dev/null
  else
    if [ -e "$APKX_HOME" ]; then
      backup="${APKX_HOME}.bak.$(date +%s)"
      printf '\n  \033[1;33m⚠\033[0m Existing non-git directory found at %s; moving to %s\n' "$APKX_HOME" "$backup"
      mv "$APKX_HOME" "$backup"
    fi
    printf '\n  \033[0;34m▸\033[0m Cloning apkx from %s into %s...\n' "$APKX_REPO_URL" "$APKX_HOME"
    git clone --depth 1 --branch "$APKX_BRANCH" "$APKX_REPO_URL" "$APKX_HOME"
  fi
}

initialize_apkx_toolchain() {
  apkx_bin="$1"
  printf '\n  \033[0;34m▸\033[0m Initializing bundled framework & signing keystore...\n'
  "$apkx_bin" framework >/dev/null 2>&1 || true
  "$apkx_bin" setup >/dev/null 2>&1 || true
}

# ---- PATH linking & shell profile persistence -------------------------------------------

link_binary_to_path() {
  binary_path="$1"
  cmd_name="$2"
  [ -n "$binary_path" ] && [ -f "$binary_path" ] || return 1
  chmod +x "$binary_path" 2>/dev/null || true

  # 1. Termux environment
  is_termux && for termux_dir in "${PREFIX:-}/bin" "/data/data/com.termux/files/usr/bin"; do
    if [ -n "$termux_dir" ] && [ -d "$termux_dir" ] && [ -w "$termux_dir" ]; then
      if [ "$binary_path" != "$termux_dir/$cmd_name" ]; then
        ln -sf "$binary_path" "$termux_dir/$cmd_name" 2>/dev/null || true
      fi
      if [ -x "$termux_dir/$cmd_name" ]; then
        printf '  \033[0;32m✔\033[0m Linked %s -> %s/%s\n' "$cmd_name" "$termux_dir" "$cmd_name"
        return 0
      fi
    fi
  done

  # 2. Standard POSIX: search current PATH for writable user/system bin directories
  old_ifs=$IFS
  IFS=:
  for dir in $PATH; do
    [ -n "$dir" ] || continue
    case "$dir" in
      /usr/local/bin|/opt/homebrew/bin|"$HOME/.local/bin"|"$HOME/bin")
        if [ -d "$dir" ] && [ -w "$dir" ] && [ "$dir" != "$(dirname "$binary_path")" ]; then
          ln -sf "$binary_path" "$dir/$cmd_name" 2>/dev/null || true
          if [ -x "$dir/$cmd_name" ]; then
            IFS=$old_ifs
            printf '  \033[0;32m✔\033[0m Linked %s -> %s/%s\n' "$cmd_name" "$dir" "$cmd_name"
            return 0
          fi
        fi
        ;;
    esac
  done
  IFS=$old_ifs

  return 1
}

link_apkx_to_path() {
  bin_dir="$1"
  link_binary_to_path "$bin_dir/$APKX_CMD" "$APKX_CMD"
}

installed_apkx_is_first_on_path() {
  bin_dir="$1"
  active=$(command -v "$APKX_CMD" 2>/dev/null) || return 1
  real_apkx="$bin_dir/$APKX_CMD"

  if [ "$active" = "$real_apkx" ]; then
    return 0
  fi

  if [ -L "$active" ]; then
    target=$(readlink "$active" 2>/dev/null || true)
    case "$target" in
      /*) [ "$target" = "$real_apkx" ] && return 0 ;;
      *) [ "$(cd "$(dirname "$active")" 2>/dev/null && pwd)/$target" = "$real_apkx" ] && return 0 ;;
    esac
  fi

  return 1
}

print_not_on_path_message() {
  bin_dir="$1"

  printf '\n  apkx is installed in %s, but your shell PATH is not updated in this window yet.\n' "$bin_dir"

  config_file=$(shell_config_file)
  if ! config_file_mentions_path "$config_file" "$bin_dir"; then
    prompt_add_path_to_profile "$bin_dir" "$APKX_CMD" || true
  fi

  printf '\n  To activate the new PATH in your current terminal session, run:\n\n    source %s\n\n' "$config_file"
  printf '  Then run: %s\n' "$APKX_CMD"
}

prompt_add_path_to_profile() {
  bin_dir="$1"
  label="${2:-apkx}"
  [ -n "$bin_dir" ] || return 0

  config_file=$(shell_config_file)
  command=$(path_update_command "$bin_dir")

  if config_file_mentions_path "$config_file" "$bin_dir"; then
    export PATH="$bin_dir:$PATH"
    return 0
  fi

  if have_tty; then
    exec 3<>/dev/tty
    printf '\n  Add %s (%s) to your PATH in %s? [Y/n] ' "$label" "$bin_dir" "$config_file" >&3
    if ! IFS= read -r answer <&3; then
      answer=
    fi
    exec 3>&-

    case "$answer" in
      n|N|no|NO) return 1 ;;
      *) ;;
    esac
  fi

  mkdir -p "${config_file%/*}"
  touch "$config_file"
  printf '\n# %s\n%s\n' "$label" "$command" >> "$config_file"
  printf '  \033[0;32m✔\033[0m Added %s to PATH in %s.\n' "$label" "$config_file"

  export PATH="$bin_dir:$PATH"
}

shell_config_file() {
  if is_termux; then
    printf '%s/.bashrc' "$HOME"
    return 0
  fi

  case "$(basename "${SHELL:-sh}")" in
    fish) printf '%s/.config/fish/config.fish' "$HOME" ;;
    zsh)
      if [ -f "${ZDOTDIR:-$HOME}/.zshrc" ]; then
        printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"
      elif [ -f "${ZDOTDIR:-$HOME}/.zprofile" ]; then
        printf '%s/.zprofile' "${ZDOTDIR:-$HOME}"
      else
        printf '%s/.zshrc' "${ZDOTDIR:-$HOME}"
      fi
      ;;
    bash|*)
      if [ -f "$HOME/.bashrc" ]; then
        printf '%s/.bashrc' "$HOME"
      elif [ -f "$HOME/.bash_profile" ]; then
        printf '%s/.bash_profile' "$HOME"
      else
        printf '%s/.profile' "$HOME"
      fi
      ;;
  esac
}

path_update_command() {
  bin_dir="$1"
  display_dir="$bin_dir"
  if [ -n "${HOME:-}" ] && case "$bin_dir" in "$HOME"/*) true;; *) false;; esac; then
    display_dir="\$HOME${bin_dir#"$HOME"}"
  fi

  case "$(basename "${SHELL:-sh}")" in
    fish) printf 'fish_add_path "%s"' "$display_dir" ;;
    *) printf 'export PATH="%s:$PATH"' "$display_dir" ;;
  esac
}

config_file_mentions_path() {
  config_file="$1"
  target="$2"

  [ -f "$config_file" ] || return 1
  if grep -Fq "$target" "$config_file"; then
    return 0
  fi
  if [ -n "${HOME:-}" ] && case "$target" in "$HOME"/*) true;; *) false;; esac; then
    rel_path="\$HOME${target#"$HOME"}"
    if grep -Fq "$rel_path" "$config_file"; then
      return 0
    fi
  fi
  return 1
}

have_tty() {
  ( : <>/dev/tty ) 2>/dev/null
}

apkx_installer_main "$@"
