# apkx

[English](./README.md) | 简体中文

**apkx** 是一个集 **Android 逆向重打包、Split APK 合并、AAR/Go Native 插件注入、真机一键编译安装调试、APK 体积分析与 AI 无人值守烟测** 于一体的全能命令行工具。

仓库 `bin/` 目录已直接内置全套逆向与重打包组件（已内置全公开化 Android 系统框架的 `apktool` 3.0.3、`apksigner`、`baksmali`、`smali`、`dx`、`dex2jar`、`reconstruct`、`jd-gui` 1.6.6），首次签名时通过 `keytool` 自动在本地生成标准 `debug.keystore`，**克隆下来即可开箱即用**。

---

## 核心特性

- **开箱即用**：内置最新版 `apktool` 3.0.3（已将内置 `prebuilt/android-framework.jar` 的系统资源全部设为 `PUBLIC`，彻底解决 `android:color/* is private` 报错）、`jd-gui`（`apkx jd`）及全套逆向 JAR 工具链。
- **APKM / XAPK / APKS 一键转独立单包 (`apkx convert`)**：自动识别 Base APK，合并所有 Split 包的 `lib/` 与 `assets/`，自动清理 `AndroidManifest.xml` 中的 Split 校验限制，内置 Google Play PairIP `LicenseCheck` 自动绕过，并完成 `zipalign -p 4` 对齐与签名。
- **双引擎一键反编译 (`apkx decode`)**：一条命令同时执行 `apktool d`（解码 `smali/` 与资源）和 `jadx`（生成 `source/` Java 源码）。
- **Java 插件与 Go Native 自动注入 (`apkx plugin` / `apkx native` / `apkx inject`)**：自动编译关联的 Gradle 插件工程或 `gomobile` Go 原生库，通过 `d8` + `baksmali` 转换为 smali 并自动注入到指定的 `smali_classesN` 目录。
- **多包名/多渠道克隆打包 (`apkx release --all` / `apkx release --variant`)**：支持按配置自动替换 `applicationId` 打出多渠道共存克隆包，打包后自动还原 Manifest。
- **单文件 Smali 智能关联反编译 (`apkx jadx`)**：自动扫描单个 `.smali` 文件引用的所有关联类，结合 `resources.arsc` 与 `mapping.jobf` 反混淆配置交由 `jadx` 精准还原 Java 代码。
- **真机一键运行与调试流**：
  - 编译 → 安装（签名冲突时自动卸载重装）→ 自动解析 Launch Activity 启动 → 附着彩色 `logcat`（`apkx run` / `apkx -r`）。
  - **日志与崩溃监控**：支持实时日志（`apkx log`）、按 PID 过滤（`apkx log --pid`）、定时抓取 N 秒落盘退出（`apkx log 10`）以及双通道 Crash 专项监控（`apkx crash` / `-x`）。
  - **设备工具箱**：设备列表与硬件/系统/电量详情（`apkx devices` / `-d`）、一键切换 WiFi 调试（`apkx wifi` / `-w`）与切回 USB（`apkx usb`）、一键截屏并打开预览（`apkx screen` / `-p`）。
- **APK 信息、体积与 64K 方法数体检 (`apkx info` / `-s`)**：一站式展示包名/版本/SDK/入口 Activity、DEX/`lib/`/`res/`/`assets/` 占比、所有 `.so` 动态库明细及 DEX 方法数占 64K 上限比例。
- **AI Agent 无人值守友好模式**：
  - `apkx build` (`-b`)：无需连接手机的纯构建与签名。
  - `apkx test` (`-t`)：全自动真机烟测（构建 → 安装 → 启动 → 等待 N 秒 → 检查 PID 存活 → 扫描崩溃 → 截图留档 → 输出 `[TEST] RESULT: PASS/FAIL`）。
  - `apkx log 10`：定时抓取 10 秒日志落盘后自动退出，杜绝 AI 调用无限流卡死。

---

## 安装与使用

```bash
git clone https://github.com/owner888/apkx.git
ln -s "$(pwd)/apkx/bin/apkx" /usr/local/bin/apkx

# 检查环境状态
apkx doctor

# （可选）安装为 Pig Coding Agent 技能插件
pig install git:github.com/owner888/apkx
```

---

## 快速上手

### 1. 逆向解包与构建
```bash
# 反编译 APK 到 <name>/smali 和 <name>/source
apkx decode app.apk

# 将 APKM / XAPK Split 捆绑包合并转换为独立签名的单 APK
apkx convert bundle.apkm

# 回编当前 smali 工程（或编译 Gradle 工程），对齐并签名
apkx build                  # 或: apkx -b

# 完整 Release 打包（编译注入 Native + Plugin + Release APK）
apkx release                # 或: apkx -R
apkx release --all          # 打包 .apkx.conf 中配置的所有多渠道克隆包
apkx release --variant beta # 打包单个指定渠道克隆包
```

### 2. 插件注入与反编译工具
```bash
# 将独立 AAR 包注入到 smali_classes2
apkx inject library.aar smali_classes2

# 自动整理 smali 包目录到 smali_classes2/smali_classes3 并清理 .line/.source 等干扰指令
apkx adjust
apkx smali2jar

# 将 .dex 或 .java 转为 .smali
apkx smali classes.dex
apkx smali Foo.java

# 用 jadx 关联反编译单个 smali 文件（默认打开 jadx-gui，加 vim 则输出到 /tmp 并用 gvim 打开）
apkx jadx smali/smali/com/example/Foo.smali
apkx jadx smali/smali/com/example/Foo.smali vim
apkx jd classes.jar
```

### 3. 真机安装、运行与日志监控
```bash
# 编译注入插件 + 回编签名 + 安装启动 + 实时日志流
apkx run                    # 或: apkx -r
apkx run --clean            # 启动前自动清空 App 数据

# 仅安装 APK 并启动（不持续监听日志）
apkx install app.apk        # 或: apkx -i

# 实时日志流 / 按进程 PID 过滤 / 定时抓 N 秒日志退出 / 崩溃专项监控
apkx log                    # 或: apkx -l
apkx log --pid              # 按当前运行 App 的 PID 过滤日志
apkx log 10                 # 抓取 10 秒日志保存到 ./logs/ 后自动退出
apkx crash                  # 或: apkx -x
```

### 4. 设备与体检工具
```bash
# 查看已连接设备列表及型号、Android 版本、ABI、IP、存储与电量
apkx devices                # 或: apkx -d

# 列出手机已安装应用包名，并一键提取 APK（Split 多包自动合并为单包）
apkx packages               # 列出第三方包（支持过滤：apkx packages camera --all）
apkx pull GoogleCamera      # 从手机提取对应 App 并自动合并签名为独立 APK

# 对现成 APK 单独执行 zipalign 4字节对齐与签名
apkx sign app.apk

# WiFi 无线调试与截屏
apkx wifi                   # 或: apkx -w
apkx usb
apkx screen                 # 或: apkx -p

# 一站式查看 APK 包信息、各组件占比、Native .so 明细与 DEX 方法数
apkx info app.apk           # 或: apkx -s app.apk

# 真机 8 秒全自动烟测（构建→安装→启动→存活与崩溃检测→截图）
apkx test 8                 # 或: apkx -t 8
```

---

## 项目级配置 (`.apkx.conf`)

`apkx` 默认零配置即可在任意目录使用。如果你的工程包含配套的 Java/Kotlin 插件仓库、Go `gomobile` 原生工程或多渠道克隆包矩阵，可将 [`examples/.apkx.conf.example`](./examples/.apkx.conf.example) 复制到项目根目录并命名为 `.apkx.conf`。

---

## 版权与开源协议

本项目由 **[Pig Coding Agent](https://pigagent.dev)**（[github.com/owner888/pig](https://github.com/owner888/pig)）构建与维护。

Copyright (c) 2026 [Pig](https://pigagent.dev) & [owner888](https://github.com/owner888)。基于 [MIT License](./LICENSE) 开源。