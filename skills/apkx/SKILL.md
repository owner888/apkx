---
name: apkx
description: Android APK reverse engineering, split bundle (APKM/XAPK) merging, smali directory organization, single-smali decompilation with jadx, AAR/plugin/Go-native injection, repackaging/signing, APK pulling from device, and unattended ADB smoke testing via the apkx CLI. Use whenever decompiling, modifying, repackaging, inspecting, or debugging Android APKs or smali projects.
---

# Android Reverse Engineering & APK Workflow with `apkx`

Use `apkx` from `bash` for Android APK reverse engineering, `.smali` inspection/modification, split APK conversion, plugin/AAR injection, repackaging, and device debugging.

## Golden Rules for AI Agents

1. **Never block on infinite log streams**:
   - Do **not** run `apkx run` (`-r`), `apkx log` (`-l`), or `apkx crash` (`-x`) without a bounded duration in unattended tool calls, because they stream `adb logcat` indefinitely.
   - Instead, use:
     - `apkx build` (`-b`) to verify compilation/repackaging without a phone.
     - `apkx install` (`-i`) to install and launch without blocking on logs.
     - `apkx log 10` (`-l 10`) to capture 10 seconds of logs to `./logs/` and exit cleanly.
     - `apkx test 8` (`-t 8`) to run a full automated smoke test (build -> install -> launch -> wait 8s -> check PID alive -> check crash logs -> capture screenshot -> output `[TEST] RESULT: PASS/FAIL`).
2. **Check device connectivity first**:
   - Before running device commands (`install`, `pull`, `packages`, `test`, `log 10`, `screen`), run `apkx devices` (`-d`) or `adb devices` to confirm a device is online.
3. **Inspecting `.smali` as Java code**:
   - To read a `.smali` file as decompiled Java (with its referenced `L...;` classes and `mapping.jobf` automatically resolved) directly in terminal output:
     ```bash
     apkx jadx path/to/ClassName.smali cat
     ```
   - When the user asks to open a `.smali` file in Vim/MacVim (`gvim`) or `jadx-gui`:
     ```bash
     apkx jadx path/to/ClassName.smali vim   # Decompiles to /tmp/apkx/jadx and opens in gvim
     apkx jadx path/to/ClassName.smali       # Opens in jadx-gui (auto-clears stale signature cache)
     ```

## Core Commands Reference

### 1. Decode, Convert & Organize Smali
```bash
# Decode APK (or .apkm/.xapk directly) into <name>/smali and <name>/source
apkx decode app.apk
apkx decode bundle.apkm --adjust

# Merge split APKM/XAPK/APKS into a standalone signed APK (strips split flags, bypasses PairIP, keeps uncompressed assets)
apkx convert bundle.apkm

# Organize smali directories (move packages to smali_classes2 & smali_classes3) and strip .line/.source directives
apkx adjust [dir]

# Convert smali/ and smali_classes3/ into deobfuscated JARs (classes.jar, classes3.jar) for plugin compilation
apkx smali2jar [out_dir]
```

### 2. Build, Inject & Sign
```bash
# Repackage smali/ directory (or build Gradle project), zipalign (-p 4) and sign
apkx build                  # or: apkx -b

# Zipalign (-p 4) & sign an existing APK file directly
apkx sign app.apk

# Inject a standalone AAR into smali_classes2 (or custom smali_classesN)
apkx inject library.aar [smali_classes2]

# Compile & inject companion Gradle plugin or Go gomobile native library
apkx plugin
apkx native

# Build release APK or multi-variant clone packages configured in .apkx.conf
apkx release
apkx release --all
apkx release --variant <name>
```

### 3. Bytecode & Decompilation Utilities
```bash
# Convert .dex or .java into .smali
apkx smali classes.dex
apkx smali Foo.java

# Decompile single .smali with dependencies (cat for stdout, vim for gvim, omit for jadx-gui)
apkx jadx smali/smali/Foo.smali cat
apkx jadx smali/smali/Foo.smali vim

# Open JAR in bundled JD-GUI
apkx jd classes.jar
```

### 4. Device, Package Extraction & Inspection
```bash
# List connected devices & hardware/OS/battery details
apkx devices                # or: apkx -d

# List installed packages on phone (3rd-party by default; --all includes system apps)
apkx packages [keyword] [--all]

# Pull installed APK from phone by package name or keyword (auto-merges split APKs into standalone APK)
apkx pull <package|keyword>

# Inspect APK metadata (package, version, SDK, main activity), component/.so sizes & 64K DEX method count
apkx info app.apk           # or: apkx -s app.apk

# Capture device screenshot to ./screenshots/
apkx screen                 # or: apkx -p

# Switch ADB between WiFi and USB
apkx wifi [port]            # or: apkx -w
apkx usb
```