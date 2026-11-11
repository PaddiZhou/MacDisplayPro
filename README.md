# 🖥️ MacDisplayPro

**macOS 旗舰级全通用原生显示器全链路控制中心 | Universal macOS Display Control & HiDPI Studio**  
*v2.0.0 Universal Binary (`arm64` Apple Silicon M1–M6 + `x86_64` Intel) • 全屏幕类型自适应 • 动态硬件链路模式矩阵 • 零重启虚拟 HiDPI • 双架构硬件 DDC/CI • 16-bit FP16 LUT 微抖动*

[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B%20%7C%20macOS%2026%2F27-blue)]()
[![Version](https://img.shields.io/badge/version-v2.0.0-indigo)]()
[![Arch](https://img.shields.io/badge/arch-Universal%20(arm64%20%2B%20x86__64)-success)]()
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)

---

## 🌟 v2.0.0 全通用重大升级亮点 (What's New in v2.0.0)

MacDisplayPro v2.0.0 在保留 v1.0 极致调优特性的基础上，彻底重构了底层硬件检测与适配管线，实现了对**全品牌、全接口、全屏幕类型（4K / 5K / 2K / 1080p / 21:9 带鱼屏 / 苹果 Studio Display / 内置屏幕 / 高刷 VRR）**的通用支持：

1. **动态输出硬件链路矩阵 (Dynamic Output Link Matrix)**：
   - 彻底摒弃硬编码槽位，动态调用 `SLSGetDisplayOutputModeLinkDescriptions` 枚举当前显示器与接口（HDMI 2.0 / 2.1 / DP 1.4 / Thunderbolt）实际支持的所有硬件链路档位。
   - 无论是 `Pure RGB 4:4:4 Full Range (0-255)`、`10-bit RGB`、`12-bit YCbCr 4:2:2 HDR10` 还是高刷 VRR 链路，均支持一键直达与无缝切换，并提供智能防降级守护。
2. **真正的物理尺寸与 PPI 感知引擎**：
   - 通过 `CGDisplayScreenSize` 精准获取毫米级物理长宽、对角线英寸与物理 PPI（例如 `27.0 吋 • 163 PPI`）。
   - 依据 PPI 与面板比例为各类显示器量身推荐最佳 HiDPI 缩放，摆脱单一固定分辨率依赖。
3. **基于 EDID 硬件指纹的独立持久化配置**：
   - 摒弃重启即失效的临时 `CGDirectDisplayID`，全面采用由 `VendorID + ModelID + SerialNumber` 构成的硬件唯一哈希作为记忆 Key。
   - 多显示器独立记忆：为每台显示器独立保存常用默认分辨率、RGB 守护状态与情景参数。
4. **自由星标最爱分辨率**：
   - 任意分辨率卡片右上角均提供交互式 ★ 星标按钮，点击即可将任意 HiDPI / 原生模式设为该显示器的常用默认项。
5. **安全可逆的调校防护**：
   - 新增一键重置 GPU 硬件 LUT 伽马表至系统原生默认（`ColorSync` 还原）。
   - 新增一键恢复 macOS 系统默认 Dock 网格尺寸，所有操作均完全安全可逆。

> 💡 **版本兼容说明**：GitHub Releases 页面同时保留了最初的 **`v1.0.0`**（专注 4K@60Hz HDMI 2.0 点对点极限调优），如需原版体验可随时下载旧版本。

---

## ✨ 核心特性 (Key Features)

### 1. 🔍 零重启 2x Retina HiDPI 与整数倍像素对齐引擎
* **原生 CGS 深度模式切换 (`CGSConfigureDisplayMode`)**：直接枚举并切换底层 `kCGS16BitFloat (Depth=8)` 64-bit RGBA FP16 视网膜缩放模式。
* **方式 A — 零重启虚拟 HiDPI 镜像 (`CGVirtualDisplay`)**：针对不支持原生 HiDPI 的 1080p / 2K / 带鱼屏显示器，无需关闭 SIP 或重启系统，实时创建 2x Retina 虚拟主屏并通过硬件加速镜像输出。
* **方式 B — 系统级 EDID Override Plist 生成器**：一键生成自定义 `scale-resolutions` 注入脚本与恢复配置。

### 2. 🎨 动态输出硬件链路直通与 RGB 4:4:4 解锁
* **痛点解决**：在 Mac 通过 HDMI 连接显示器时，macOS 常默认协商为 `YCbCr 4:2:0 / 4:2:2 + Limited Range (16-235)`，导致彩色图标边缘、红蓝代码文字出现半像素彩色阶梯毛刺。
* **动态链路枚举 (`SLSGetDisplayOutputModeLinkDescriptions`)**：
  * **一键锁定最佳 `Pure RGB 4:4:4 + Full Range 0-255`**：在带宽范围内实现 100% 完整全色度像素对齐，彻底消除 YCbCr 色度半采样伪影。
  * **一键直通 `12-bit HDR10`**：直通显示器原生 12-bit HDR 硬件解码通道。
  * **防回退守护**：当在系统设置中切换 HDR/SDR 导致系统回退至 `YCbCr` 时，自动守护并恢复 `Pure RGB 4:4:4 Full Range`。

### 3. 💎 16-bit FP16 浮点渲染 + 1024 级蓝噪声硬件 LUT 微抖动 (FRC Dithering)
* 结合 `CGS Depth=8 (FP16)` 帧缓冲与 `CGSetDisplayTransferByTable` 1024 级硬件查找表，注入去相关 R/G/B 亚最低有效位（Sub-LSB）微抖动，在物理链路上呈现丝滑无断层的深色渐变过渡。
* 内置 **10 组专业 ColorSync ICC 色彩配置一键切换**（包含 `🍎 Apple Display P3`、`Apple HD 709-A`、`Apple RGB`、`sRGB`、`Adobe RGB`、`BT.2020` 等），自动适配并与系统设置实时双向同步。

### 4. ☀️ 双架构硬件 DDC/CI 引擎与双向实时同步 (`arm64` + `x86_64`)
* **Apple Silicon (`arm64`)**：直接通过私有 `IOAVServiceCreateWithService` / `IOAVServiceReadI2C` / `IOAVServiceWriteI2C` 驱动 DCP 控制器。
* **Intel Mac (`x86_64`)**：自动适配 `IOFramebuffer` / `IOI2CInterface` 硬件总线。
* 支持 **硬件亮度 (`VCP 0x10`)、对比度 (`0x12`)、音量 (`0x62`)、静音 (`0x8D`)、输入源切换 (`0x60`)、三原色硬件增益 (`0x16/0x18/0x1A`)、硬件锐度校准 (`0x87`)**。
* **原生键盘快捷键联动 + 双向轮询同步**：支持使用 Mac 键盘亮度键/音量键直接控制外接显示器并弹出原生毛玻璃 HUD；无论是通过 Apple 系统设置、控制中心还是显示器物理按键修改状态，App 界面均实时同步。

### 5. ✨ 图标抗锯齿与像素边缘优化器
* 自动对齐 Dock 整数倍像素网格（`48pt / 56pt / 64pt` 整数分频），清理残留 `@1x` 图标缓存，并修复第三方应用在 macOS `IconServices` 下因强制抠图重采样导致的圆角黑圈与边缘锯齿，支持随时一键恢复系统默认设置。

---

## 🚀 快速开始 (Quick Start)

### 方式一：直接下载预编译通用版 (Universal Binary)
前往 [**Releases**](../../releases) 页面下载最新的 `MacDisplayPro-v2.0.0-Universal.zip`，解压后直接运行 `MacDisplayPro.app`（原生兼容 Apple Silicon M1–M6 与 Intel Mac）。

### 方式二：从源码编译打包
```bash
git clone https://github.com/PaddiZhou/MacDisplayPro.git
cd MacDisplayPro
./build_app.sh
```

---

## 🛠️ 命令行接口 (CLI Usage)

`MacDisplayPro` 内置完整的无头 CLI 模式，可用于脚本自动化或开机自启恢复：

```bash
# 查看所有显示器硬件遥测、模式列表与当前硬件链路状态
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --cli

# 一键锁定当前屏幕参数为开机自启默认项
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --lock-default

# 一键执行图标与字体抗锯齿修复
./MacDisplayPro.app/Contents/MacOS/MacDisplayPro --fix-icons
```

---

## 📂 项目架构 (Project Structure)

```text
MacDisplayPro/
├── Package.swift                 # SwiftPM 配置 (CDisplayBridge + MacDisplayPro)
├── Info.plist                    # 应用 Bundle 元数据 (v2.0.0)
├── build_app.sh                  # 双架构 Universal Binary (arm64 + x86_64) 编译与打包脚本
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
        ├── StudioMainWindow.swift
        ├── DisplayModels.swift
        └── DesignSystem.swift
```

---

## 📄 开源协议 (License)

本项目基于 [MIT License](LICENSE) 开源。
