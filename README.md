# 🖥️ MacDisplayPro

**macOS 旗舰级原生显示器全链路控制中心 | Native macOS Display Control & HiDPI Studio**  
*Universal Binary (`arm64` Apple Silicon M1–M6 + `x86_64` Intel) • Zero-Reboot Virtual HiDPI • HDMI RGB 4:4:4 Unlocker • Dual-Arch Hardware DDC/CI • 16-bit FP16 LUT Dithering*

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20macOS%2026%2F27-blue)]()
[![Arch](https://img.shields.io/badge/arch-Universal%20(arm64%20%2B%20x86__64)-success)]()
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)

---

## ✨ 核心特性 (Key Features)

### 1. 🔍 零重启 2x Retina HiDPI 与整数倍像素对齐引擎
* **原生 CGS 深度模式切换 (`CGSConfigureDisplayMode`)**：直接枚举并切换底层 `kCGS16BitFloat (Depth=8)` 64-bit RGBA FP16 视网膜缩放模式。
* **方式 A — 零重启虚拟 HiDPI 镜像 (`CGVirtualDisplay`)**：针对不支持原生 HiDPI 的 1080p / 2K / 带鱼屏显示器，无需关闭 SIP 或重启系统，实时创建 2x Retina 虚拟主屏并通过硬件加速镜像输出。
* **方式 B — 系统级 EDID Override Plist 生成器**：一键生成自定义 `scale-resolutions` 注入脚本与恢复配置。

### 2. 🎨 免换线 HDMI 2.0 `Pure RGB 4:4:4 + Full Range (0-255)` 强制解锁
* **痛点解决**：在 Apple Silicon Mac 通过内置 HDMI 2.0 (`18 Gbps` / `594 MHz`) 连接 4K 60Hz 显示器时，macOS 常默认协商为 `10-bit YCbCr 4:2:0 / 4:2:2 + Limited Range (16-235)`，导致彩色图标边缘、红蓝代码文字出现半像素彩色阶梯毛刺。
* **底层直通 (`SLSSetDisplayOutputMode` / `SLSGetDisplayOutputModeLinkDescriptions`)**：
  * **一键锁定 `[4]` 档 (`8-bit Pure RGB 4:4:4 + Full Range 0-255 + SDR`)**：在 `17.82 Gbps` 带宽内实现 100% 完整 `3840 × 2160` 全色度像素对齐，彻底消除 YCbCr 色度半采样伪影。
  * **一键直通 `[1]` 档 (`12-bit HDR10 + YCbCr 4:2:2`)**：绕过 macOS 系统设置仅能开启 `[0]` 档 (`10-bit 4:2:0`) 的限制，直通显示器原生 12-bit HDR 硬件解码通道。
  * **防回退守护**：当用户在系统设置中开关 HDR 导致系统回退至 `YCbCr` 时，自动检测并恢复 `Pure RGB 4:4:4 Full Range`。

### 3. 💎 16-bit FP16 浮点渲染 + 1024 级蓝噪声硬件 LUT 微抖动 (FRC Dithering)
* 结合 `CGS Depth=8 (FP16)` 帧缓冲与 `CGSetDisplayTransferByTable` 1024 级硬件查找表，注入去相关 R/G/B 亚最低有效位（Sub-LSB）蓝噪声微抖动，在 `8-bit RGB 4:4:4` 物理链路上实现无断层的深色渐变过渡。
* 内置 **10 组专业 ColorSync ICC 色彩配置一键切换**（包含 `🍎 Apple Display P3`、`Apple HD 709-A`、`Apple RGB`、`sRGB`、`Adobe RGB`、`BT.2020` 等），自动适配 Apple Silicon HDMI 专有的 `"HDMI HD"` ColorSync 槽位，并与系统设置实时双向同步。

### 4. ☀️ 双架构硬件 DDC/CI 引擎与双向实时同步 (`arm64` + `x86_64`)
* **Apple Silicon (`arm64`)**：直接通过私有 `IOAVServiceCreateWithService` / `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` 驱动 DCP 控制器。
* **Intel Mac (`x86_64`)**：自动回退至 `IOFramebuffer` / `IOI2CInterface` 硬件总线。
* 支持 **硬件亮度 (`VCP 0x10`)、对比度 (`0x12`)、音量 (`0x62`)、静音 (`0x8D`)、输入源切换 (`0x60`)、三原色硬件增益 (`0x16/0x18/0x1A`)、硬件锐度校准 (`0x87`)**。
* **原生键盘快捷键联动 + 双向轮询同步**：支持使用 Mac 键盘亮度键/音量键直接控制外接显示器并弹出原生毛玻璃 HUD；无论是通过 Apple 系统设置、控制中心还是显示器物理按键修改状态，App 界面均实时同步。

### 5. ✨ macOS 26/27 App 图标抗锯齿优化器
* 自动对齐 Dock 整数倍像素网格（`64pt = 128×128 @2x` 严格 `2:1` 整数分频），清理残留 `@1x` 图标缓存，并修复第三方应用在 macOS 27 `IconServices` 下因强制主体抠图重采样导致的圆角黑圈与边缘锯齿。

---

## 🚀 快速开始 (Quick Start)

### 方式一：直接下载预编译通用版 (Universal Binary)
前往 [**Releases**](../../releases) 页面下载最新的 `MacDisplayPro-Universal-Portable.zip`，解压后直接运行 `MacDisplayPro.app`（同时原生支持 Apple Silicon 与 Intel Mac）。

### 方式二：从源码编译打包
```bash
git clone https://github.com/PaddiZhou/MacDisplayPro.git
cd MacDisplayPro
./build_app.sh
open MacDisplayPro.app
```

---

## 🛠️ 命令行接口 (CLI Usage)

`MacDisplayPro` 内置完整的无头 CLI 模式，可用于脚本自动化或开机自启恢复：

```bash
# 查看所有显示器硬件遥测、模式列表与当前 HDMI 信号链路状态
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --cli

# 一键锁定黄金默认配置 (1920x1080 HiDPI 2x + 92% 亮度 + Apple Display P3 + Pure RGB 4:4:4 Full Range)
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --lock-default

# 一键执行图标与字体抗锯齿修复 + 强制 RGB 4:4:4
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --fix-icons
```

---

## 📂 项目架构 (Project Structure)

```text
MacDisplayPro/
├── Package.swift                 # SwiftPM 配置 (CDisplayBridge + MacDisplayPro)
├── Info.plist                    # 应用 Bundle 元数据
├── build_app.sh                  # 双架构 Universal Binary (arm64 + x86_64) 编译与签名打包脚本
└── Sources/
    ├── CDisplayBridge/           # Objective-C / C 底层硬件桥接层
    │   ├── include/CDisplayBridge.h
    │   └── CDisplayBridge.m      # SkyLight / CGS / CGVirtualDisplay / IOAVService / IOI2C / ColorSync
    └── MacDisplayPro/            # Swift / SwiftUI 核心引擎与界面
        ├── MacDisplayProApp.swift
        ├── DisplayStore.swift
        ├── ColorAndHardwareEngine.swift
        ├── DDCController.swift
        ├── HiDPIManager.swift
        ├── VirtualDisplayManager.swift
        ├── AutoAdaptEngine.swift
        ├── IconAntiAliasingOptimizer.swift
        ├── XDRBrightnessEngine.swift
        ├── HUDManager.swift
        ├── MenuBarView.swift
        └── StudioMainWindow.swift
```

---

## 📄 开源协议 (License)

本项目基于 [MIT License](LICENSE) 开源。
