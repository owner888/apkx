# apkx — Project Rules & Architecture

**apkx** is an all-in-one Android APK reverse engineering, repackaging, AAR/Go-native plugin injection, real-device debugging, and AI-friendly workflow CLI.

Crafted by **[Pig Coding Agent](https://pigagent.dev)** ([github.com/owner888/pig](https://github.com/owner888/pig)).
Copyright (c) 2026 Pig (https://pigagent.dev) & owner888.

---

## Layout

```text
bin/
  apkx                      Main CLI entry point (resolves symlinks and sources lib/*.sh)
  apktool_3.0.3.jar         Bundled Apktool 3.0.3 (patched with publicized Android framework)
  apksigner.jar             Bundled Android APK Signer
  baksmali-2.5.2.jar        Bundled Baksmali disassembler
  smali-2.5.2.jar           Bundled Smali assembler
  dx.jar                    Bundled DX tool
  dex-tools-2.1/            Bundled dex2jar suite
  reconstruct-cli-1.3.22.jar Bundled ProGuard mapping deobfuscator
  jd-gui-1.6.6.jar          Bundled JD-GUI 1.6.6 (`apkx jd`)
lib/
  core.sh                   ANSI colors, logging, cross-platform sed helpers, toolchain & config loader
  doctor.sh                 `doctor`, `setup`, and `framework` commands
  decode.sh                 `decode` (apktool + jadx) and `convert` (APKM/XAPK merger + PairIP bypass)
  build.sh                  `build`, `package`, multi-variant clones, AAR/Java-plugin/Go-native injection
  smali.sh                  `s2j`, `jadx` single-smali dependency decompiler, `j2s`, `s2java`, `d2s`, `j2d`
  device.sh                 `run`, `brl`, `logcat`, `debug`, `crash`, `wifi`, `usb`, `device`, `screen`
  inspect.sh                `pkginfo`, `size` (component/.so/64K DEX method analysis), `version`
  ai.sh                     AI unattended modes: `build-only` (-b), `test` (-t), `log-dump` (-g)
examples/
  .apkx.conf.example        Optional project-level configuration template
skills/
  apkx/SKILL.md             Pig Coding Agent skill definition (`pig install git:github.com/owner888/apkx`)
```

---

## AI Agent Workflow Guidelines

When an AI coding agent (`pig` or another agent) works with an Android project using `apkx`:

1. **Always check device connectivity before running device commands**:
   - Use `apkx -b` (`--build-only`) for pure compilation/repackaging checks when no device is needed.
   - Before running `apkx -r` / `apkx -t`, verify a device is online with `adb devices` or `apkx -d`.
2. **Never hang on infinite log streams**:
   - Do **not** invoke `apkx -l`, `apkx -r`, or `apkx -x` in unattended tool calls without a timeout, as they stream `adb logcat` indefinitely.
   - Instead, use `apkx -g <seconds>` (`--log-dump <seconds>`) to capture bounded logs to `./logs/` and exit cleanly, or `apkx -t <seconds>` (`--test`) for end-to-end automated smoke testing.
3. **Verify syntax after editing scripts**:
   ```bash
   for f in bin/apkx lib/*.sh; do bash -n "$f"; done
   ```

---

## Coding Conventions

- **Out-of-the-box portability**: All core reverse-engineering JARs live in `bin/` so a fresh `git clone` works immediately without external setup.
- **Cross-platform shell compatibility (macOS BSD + Linux GNU)**:
  - Always use `sed_inplace` and `sed_regex_inplace` from `lib/core.sh` instead of raw `sed -i`.
  - Use `perl -0777 -pi -e` for multi-line regex transformations (such as PairIP bypass in `lib/decode.sh`) rather than external Python scripts.
- **No hardcoded personal paths or usernames**:
  - Never hardcode personal home directories, usernames, private IPs, or machine-specific paths in scripts, comments, or documentation.
  - Project-specific paths (like companion Gradle plugin or Go native directories) belong in `.apkx.conf` (ignored by Git) with generic defaults in `lib/core.sh`.
- **Bilingual documentation**:
  - `README.md` and `README.zh-CN.md` must stay synchronized whenever commands, flags, or configuration options change.