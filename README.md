# apkx

English | [简体中文](./README.zh-CN.md)

**apkx** is an all-in-one Android reverse engineering, repackaging, AAR/Go-native plugin injection, real-device debugging, and AI-friendly automation workflow CLI.

All required reverse-engineering JARs (`apktool` 3.0.3 with pre-publicized Android framework, `apksigner`, `baksmali`, `smali`, `dx`, `dex2jar`, `reconstruct`, and `jd-gui` 1.6.6) are bundled directly in `bin/` (and a local `debug.keystore` is auto-generated via `keytool` on first run) so it works **out of the box** right after `git clone`.

---

## Highlights

- **Zero-Setup Out of the Box**: Bundled with `apktool` 3.0.3 (pre-patched with publicized Android framework resources to prevent `android:color/* is private` errors), `smali`/`baksmali`, `apksigner`, `dex2jar`, `reconstruct`, `jd-gui`, and automatic local `debug.keystore` generation.
- **Split APK (`APKM` / `XAPK` / `APKS`) to Standalone APK**: Automatically locates the base APK, merges split native libraries (`lib/`) and `assets/`, strips split restrictions from `AndroidManifest.xml`, bypasses PairIP `LicenseCheck`, zipaligns (`-p 4`), and signs.
- **One-Command Decode**: Runs `apktool d` (into `smali/`) and `jadx` (into `source/`) in one go.
- **Plugin & Go Native Injection**: Compiles companion Gradle Java/Kotlin plugins or `gomobile` Go native libraries into `.aar`, converts bytecode via `d8` + `baksmali`, and injects classes, resources, and `.so` libraries directly into target `smali_classesN` directories.
- **Multi-Variant Clone Packaging**: Repackages APKs with custom `applicationId`s and filename suffixes for side-by-side installation or vendor package whitelisting (`apkx release --all` / `apkx release --variant <name>`).
- **Smart Single-Smali Decompilation**: Extracts referenced `L...;` classes from a `.smali` file and decompiles them together with `resources.arsc` and `mapping.jobf` in `jadx`.
- **Real-Device Run & Debug Suite**:
  - One-command build -> install (with automatic uninstall-reinstall fallback on signature conflict) -> resolve launch activity -> stream colored `logcat` (`apkx run` / `apkx -r`).
  - Dedicated Crash/ANR monitor (`apkx crash` / `apkx -x`), PID-filtered log streams (`apkx log --pid`), and bounded N-second log dumps (`apkx log 10`).
  - One-command ADB over WiFi (`apkx wifi` / `apkx -w`) & USB switch (`apkx usb`), screenshot capture (`apkx screen` / `apkx -p`), and connected devices & hardware details (`apkx devices` / `apkx -d`).
- **APK Metadata, Size & 64K DEX Method Analyzer**: Displays package/SDK/activity info, breaks down APK size by DEX, `lib/`, `res/`, `assets/`, lists every `.so` file, and calculates DEX method references against the 64K limit (`apkx info` / `apkx -s`).
- **AI Agent Unattended Modes**:
  - `apkx build` (`-b`): Headless build & sign without requiring a connected phone.
  - `apkx test` (`-t`): End-to-end automated smoke test (build -> install -> launch -> PID alive check -> crash scan -> screenshot -> `[TEST] RESULT: PASS/FAIL`).
  - `apkx log 10`: Captures `10` seconds of logs to `./logs/` and exits cleanly without blocking.

---

## Installation

```bash
git clone https://github.com/owner888/apkx.git
ln -s "$(pwd)/apkx/bin/apkx" /usr/local/bin/apkx

# Check environment & bundled tools
apkx doctor

# (Optional) Install as a Pig Coding Agent skill
pig install git:github.com/owner888/apkx
```

---

## Quick Start

### 1. Build & Reverse
```bash
# Decode APK into <name>/smali and <name>/source
apkx decode app.apk

# Convert split APKM / XAPK bundle into a standalone signed APK
apkx convert bundle.apkm

# Build, zipalign & sign current smali project (or Gradle project)
apkx build                  # or: apkx -b

# Full release package (native + plugin + release APK or variants)
apkx release                # or: apkx -R
apkx release --all          # Build all clone variants configured in .apkx.conf
apkx release --variant beta # Build a single named clone variant
```

### 2. Plugin & Decompile
```bash
# Inject an AAR into smali_classes2
apkx inject library.aar smali_classes2

# Organize smali packages across smali_classes2/smali_classes3 & strip .line/.source directives
apkx adjust
apkx smali2jar

# Convert .dex or .java source into .smali
apkx smali classes.dex
apkx smali Foo.java

# Decompile a single .smali file (with referenced classes & mapping) in jadx-gui or open in gvim
apkx jadx smali/smali/com/example/Foo.smali
apkx jadx smali/smali/com/example/Foo.smali vim
apkx jd classes.jar
```

### 3. Run & Debug (ADB)
```bash
# Build + install + launch + stream live logcat
apkx run                    # or: apkx -r
apkx run --clean            # Clear app data before launching

# Only install APK & launch app (no log stream)
apkx install app.apk        # or: apkx -i

# Stream logcat, filter by PID, dump N seconds to file, or monitor crashes
apkx log                    # or: apkx -l
apkx log --pid              # Filter logcat by running app PID
apkx log 10                 # Capture 10s of logcat to ./logs/ and exit cleanly
apkx crash                  # or: apkx -x
```

### 4. Device & Utilities
```bash
# Connected devices & hardware/OS/battery details
apkx devices                # or: apkx -d

# List installed packages & pull APK from device (auto-merges split APKs)
apkx packages               # List 3rd-party packages (or: apkx packages camera --all)
apkx pull GoogleCamera      # Pull & merge installed app into standalone APK

# Zipalign & sign an existing APK
apkx sign app.apk

# WiFi debugging & screenshots
apkx wifi                   # or: apkx -w
apkx usb
apkx screen                 # or: apkx -p

# APK metadata, component/.so breakdown & 64K method count
apkx info app.apk           # or: apkx -s app.apk

# Automated 8-second smoke test on connected device
apkx test 8                 # or: apkx -t 8
```

---

## Project Configuration (`.apkx.conf`)

`apkx` works out of the box with zero configuration. For projects that use companion Java/Kotlin Gradle plugins, Go `gomobile` native libraries, or multi-variant clone builds, copy [`examples/.apkx.conf.example`](./examples/.apkx.conf.example) to `.apkx.conf` in your project root.

---

## Credits & License

Crafted by **[Pig Coding Agent](https://pigagent.dev)** ([github.com/owner888/pig](https://github.com/owner888/pig)).

Copyright (c) 2026 [Pig](https://pigagent.dev) & [owner888](https://github.com/owner888). Released under the [MIT License](./LICENSE).