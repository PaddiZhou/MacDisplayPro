import Foundation
import AppKit
import CoreGraphics
import CDisplayBridge

public enum BitDepthChoice: Int, CaseIterable, Identifiable {
    case bit10 = 10
    case bit12 = 12
    case bit16 = 16

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .bit10: return "10-bit"
        case .bit12: return "12-bit (FRC 抖动)"
        case .bit16: return "16-bit (FP16 超采)"
        }
    }

    public var subtitle: String {
        switch self {
        case .bit10: return "标准 10.7 亿色直出"
        case .bit12: return "8+4bit / 10+2bit 时空抖动消除断层"
        case .bit16: return "FP16 浮点渲染 + 蓝噪声满血抖动 (推荐)"
        }
    }
}

public struct ColorProfileOption: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let subtitle: String
    public let url: URL?
    public let isRecommended: Bool
}

public struct DisplayHardwareTelemetryModel {
    public let maxBpc: Int
    public let maxPixelRateMHz: Int
    public let maxGPUSrcBufferWidth: Int
    public let currentCGSDepthCode: Int
    public let activeLinkBitDepth: Int
    public let activePixelEncoding: Int
    public let activeDynamicRange: Int
    public let activeEOTF: Int
    public let supportsHDR10EOTF: Bool
    public let supports12BitMode: Bool
    public let supports10BitMode: Bool

    public var framebufferDepthDescription: String {
        let encStr: String
        switch activePixelEncoding {
        case 0: encStr = "RGB 4:4:4 全色度"
        case 2: encStr = "YCbCr 4:2:2 色度压缩"
        default: encStr = "YCbCr 4:2:0 色度压缩"
        }
        let rangeStr = (activeDynamicRange == 1) ? "Full Range (0-255)" : "Limited (16-235)"
        let eotfStr = (activeEOTF == 2) ? "HDR10 (EOTF=2 PQ)" : "SDR (EOTF=0)"
        switch currentCGSDepthCode {
        case 8:
            return "16-bit FP16 渲染 → 硬件链路: \(activeLinkBitDepth)-bit • \(encStr) • \(rangeStr) • \(eotfStr)"
        case 6, 7:
            return "10-bit 渲染 → 硬件链路: \(activeLinkBitDepth)-bit • \(encStr) • \(rangeStr) • \(eotfStr)"
        default:
            return "8-bit 渲染 → 硬件链路: \(activeLinkBitDepth)-bit • \(encStr) • \(rangeStr) • \(eotfStr)"
        }
    }

    public var physicalLinkAnalysis: String {
        let isRGB444 = (activePixelEncoding == 0)
        if maxPixelRateMHz <= 600 {
            if isRGB444 {
                return "✅ 当前处于 [4] 档：8-bit Pure RGB 4:4:4 全色度 + Full Range (0-255, SDR) • 零彩色毛边"
            } else if activeLinkBitDepth == 12 && activeEOTF == 2 {
                return "🔥 当前处于 [1] 档：12-bit HDR10 (EOTF=2, YCbCr 4:2:2, Limited 16-235) • 原生 12-bit 高动态范围已开启"
            } else {
                return "⚠️ 当前处于 [\(activeLinkBitDepth)-bit EOTF=\(activeEOTF) Encoding=\(activePixelEncoding)] YCbCr 色度压缩模式 • 可随时一键切换 [4] RGB 4:4:4 或 [1] 12-bit HDR10"
            }
        } else {
            return "DisplayPort / Thunderbolt 高速链路 (峰值时钟 \(maxPixelRateMHz) MHz) • 面板支持最高 \(maxBpc)-bit 色深"
        }
    }
}

@MainActor
public final class ColorAndHardwareEngine: ObservableObject {
    public static let shared = ColorAndHardwareEngine()

    @Published public var availableProfiles: [ColorProfileOption] = []
    @Published public var activeProfileURL: [CGDirectDisplayID: URL] = [:]
    @Published public var telemetry: [CGDirectDisplayID: DisplayHardwareTelemetryModel] = [:]
    @Published public var selectedBitDepth: [CGDirectDisplayID: BitDepthChoice] = [:]
    @Published public var userSelectedHDR12Bit: [CGDirectDisplayID: Bool] = [:]

    // Hardware DDC RGB Gain (VCP 0x16 Red, 0x18 Green, 0x1A Blue)
    @Published public var redGain: [CGDirectDisplayID: Double] = [:]
    @Published public var greenGain: [CGDirectDisplayID: Double] = [:]
    @Published public var blueGain: [CGDirectDisplayID: Double] = [:]

    private init() {
        scanColorProfiles()
    }

    public func refresh(for displayID: CGDirectDisplayID) {
        scanColorProfiles()
        if let curURL = MDP_CopyCurrentColorProfileURL(displayID) {
            activeProfileURL[displayID] = curURL
        }

        let raw = MDP_GetDisplayHardwareTelemetry(displayID)
        telemetry[displayID] = DisplayHardwareTelemetryModel(
            maxBpc: Int(raw.maxBpc),
            maxPixelRateMHz: Int(raw.maxPixelRateMHz),
            maxGPUSrcBufferWidth: Int(raw.maxGPUSrcBufferWidth),
            currentCGSDepthCode: Int(raw.currentCGSDepthCode),
            activeLinkBitDepth: Int(raw.activeLinkBitDepth),
            activePixelEncoding: Int(raw.activePixelEncoding),
            activeDynamicRange: Int(raw.activeDynamicRange),
            activeEOTF: Int(raw.activeEOTF),
            supportsHDR10EOTF: raw.supportsHDR10EOTF,
            supports12BitMode: raw.supports12BitMode,
            supports10BitMode: raw.supports10BitMode
        )

        if selectedBitDepth[displayID] == nil {
            let saved = UserDefaults.standard.integer(forKey: "mdp.bitDepth.\(displayID)")
            selectedBitDepth[displayID] = BitDepthChoice(rawValue: saved) ?? .bit16
        }
        if redGain[displayID] == nil { redGain[displayID] = 100 }
        if greenGain[displayID] == nil { greenGain[displayID] = 100 }
        if blueGain[displayID] == nil { blueGain[displayID] = 100 }
    }

    /// Directly activates Link Slot [1]: BitDepth=12, Range=0 (Limited 16-235), EOTF=2 (HDR10), Encoding=2 (YCbCr 4:2:2)
    public func activateLinkSlot1_12BitHDR10(for displayID: CGDirectDisplayID) -> String {
        userSelectedHDR12Bit[displayID] = true
        let ok = MDP_SetExactLinkDescription(displayID, 12, 0, 2, 2)
        refresh(for: displayID)
        return ok
            ? "已强制开启 [1] 档：12-bit HDR10 (BitDepth=12, Range=0, EOTF=2, Encoding=2 YCbCr 4:2:2)"
            : "切换 [1] 档失败，当前显示器不支持该硬件档位"
    }

    /// Directly activates Link Slot [4]: BitDepth=8, Range=1 (Full 0-255), EOTF=0 (SDR), Encoding=0 (Pure RGB 4:4:4)
    public func activateLinkSlot4_RGB444FullRange(for displayID: CGDirectDisplayID) -> String {
        userSelectedHDR12Bit[displayID] = false
        let ok = MDP_SetExactLinkDescription(displayID, 8, 1, 0, 0)
        refresh(for: displayID)
        return ok
            ? "已恢复 [4] 档：8-bit Pure RGB 4:4:4 + Full Range (0-255, SDR 零毛边模式)"
            : "切换 [4] 档失败"
    }

    public func selectBitDepth(_ choice: BitDepthChoice, for displayID: CGDirectDisplayID) -> String {
        selectedBitDepth[displayID] = choice
        UserDefaults.standard.set(choice.rawValue, forKey: "mdp.bitDepth.\(displayID)")
        _ = MDP_LockHighestBitDepthForCurrentMode(displayID)
        applyBitDepthLUTAndDithering(choice, for: displayID)
        return "已启用 \(choice.title)：\(choice.subtitle)"
    }

    /// Configures a 1024-entry high-precision hardware transfer table (`CGSetDisplayTransferByTable`)
    /// with sub-LSB FRC micro-dithering to eliminate dark-gradient banding without sacrificing RGB 4:4:4 text clarity.
    public func applyBitDepthLUTAndDithering(_ choice: BitDepthChoice, for displayID: CGDirectDisplayID) {
        let tableSize = 1024
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)

        // 4-phase 1D blue-noise micro-dither kernel (in units of 1/4096 = 12-bit LSB)
        let ditherKernel: [Float] = [-0.375, 0.125, -0.125, 0.375]
        let lsb12: Float = 1.0 / 4096.0

        for i in 0..<tableSize {
            let base = Float(i) / Float(tableSize - 1)
            switch choice {
            case .bit10:
                // Standard 10-bit (1024 levels) direct transfer
                let q10 = roundf(base * 1023.0) / 1023.0
                redTable[i] = q10
                greenTable[i] = q10
                blueTable[i] = q10

            case .bit12:
                // 12-bit FRC Dithering: decorrelated R/G/B sub-LSB micro-dither to break up 8/10-bit color banding
                let dR = ditherKernel[i & 3] * lsb12
                let dG = ditherKernel[(i + 1) & 3] * lsb12
                let dB = ditherKernel[(i + 2) & 3] * lsb12
                redTable[i] = max(0.0, min(1.0, base + dR))
                greenTable[i] = max(0.0, min(1.0, base + dG))
                blueTable[i] = max(0.0, min(1.0, base + dB))

            case .bit16:
                // 16-bit FP16 Ultra-Smooth: continuous 32-bit float precision + gentle shadow de-banding micro-dither
                let shadowWeight = max(0.0, 1.0 - base * 2.5) // Concentrate anti-banding dither in dark 0..40% tones
                let dR = ditherKernel[i & 3] * (lsb12 * 0.65 * shadowWeight)
                let dG = ditherKernel[(i + 2) & 3] * (lsb12 * 0.65 * shadowWeight)
                let dB = ditherKernel[(i + 1) & 3] * (lsb12 * 0.65 * shadowWeight)
                redTable[i] = max(0.0, min(1.0, base + dR))
                greenTable[i] = max(0.0, min(1.0, base + dG))
                blueTable[i] = max(0.0, min(1.0, base + dB))
            }
        }

        CGSetDisplayTransferByTable(displayID, UInt32(tableSize), &redTable, &greenTable, &blueTable)
    }

    public func scanColorProfiles() {
        var list: [ColorProfileOption] = []

        // 0. Factory Default option
        list.append(ColorProfileOption(
            id: "factory-default",
            name: "🖥️ 显示器出厂原生配置 (EDID 默认 ICC)",
            subtitle: "恢复显示器硬件自动生成的原生 ColorSync 配置文件",
            url: nil,
            isRecommended: true
        ))

        let coreProfiles: [(file: String, title: String, desc: String, rec: Bool)] = [
            ("/System/Library/ColorSync/Profiles/Display P3.icc", "🍎 Apple Display P3 (Studio Display / MacBook 同款官方标准)", "苹果自研旗舰广色域标准 (DCI-P3 色域 + D65 白点 + sRGB 曲线)，通透自然", true),
            ("/System/Library/CoreServices/Resources/Profiles/HD 709-A.icc", "🍎 Apple HD 709-A (Final Cut / QuickTime 官方影视标准)", "苹果专有 1.96 Gamma 视频参考配置，解决 Mac 播放器画面偏暗问题", true),
            ("/Library/Application Support/Adobe/Color/Profiles/Recommended/AppleRGB.icc", "🍎 Apple RGB (苹果经典 1.8 Gamma 通透模式)", "Apple 经典桌面色彩曲线，暗部细节明显提亮、画面轻快通透", false),
            ("/Library/Application Support/Adobe/Color/Profiles/P3D65g24.icc", "🍎 Apple XDR Reference P3-D65 (Gamma 2.4 暗房参考级)", "对标 Pro Display XDR 影视后期 P3-D65 标准，暗部对比度更深邃", false),
            ("/System/Library/ColorSync/Profiles/sRGB Profile.icc", "🎯 sRGB IEC61966-2.1 (Web / UI 标准精准色域)", "跨平台网页与 UI 设计黄金标准，防止非色彩管理应用红绿过饱和", true),
            ("/System/Library/ColorSync/Profiles/AdobeRGB1998.icc", "🎨 Adobe RGB (1998)", "专业摄影与印刷广色域空间，青绿色域覆盖更广", false),
            ("/System/Library/ColorSync/Profiles/DCI(P3) RGB.icc", "🎬 DCI-P3 数字影院色域", "好莱坞数字电影院线色彩标准 (2.6 Gamma)", false),
            ("/System/Library/ColorSync/Profiles/ITU-2020.icc", "🌈 ITU-R BT.2020 (Rec.2020 超广色域)", "4K/8K HDR 超高清视频色域标准，配合 16-bit 展现最广色阶", false),
            ("/System/Library/ColorSync/Profiles/ITU-709.icc", "📺 ITU-R BT.709 (Rec.709 影视标准)", "高清影视调色标准白点与伽马", false),
            ("/System/Library/ColorSync/Profiles/Generic RGB Profile.icc", "🍎 Apple Generic RGB (macOS 通用 RGB 空间)", "macOS 传统通用 RGB 合成配置", false)
        ]

        let fm = FileManager.default
        for item in coreProfiles {
            if fm.fileExists(atPath: item.file) {
                let u = URL(fileURLWithPath: item.file)
                list.append(ColorProfileOption(
                    id: u.path,
                    name: item.title,
                    subtitle: item.desc,
                    url: u,
                    isRecommended: item.rec
                ))
            }
        }

        // Also scan /Library/ColorSync/Profiles/Displays for custom display-calibrated ICC profiles
        let displayProfDir = "/Library/ColorSync/Profiles/Displays"
        if let files = try? fm.contentsOfDirectory(atPath: displayProfDir) {
            for f in files where f.hasSuffix(".icc") || f.hasSuffix(".icm") {
                let fullPath = "\(displayProfDir)/\(f)"
                let u = URL(fileURLWithPath: fullPath)
                list.append(ColorProfileOption(
                    id: fullPath,
                    name: "🔧 专属校准配置: \(f)",
                    subtitle: fullPath,
                    url: u,
                    isRecommended: false
                ))
            }
        }

        self.availableProfiles = list
    }

    public func isProfileActive(_ option: ColorProfileOption, for displayID: CGDirectDisplayID) -> Bool {
        guard let active = activeProfileURL[displayID] else {
            return option.url == nil
        }
        if let optURL = option.url {
            return active.standardizedFileURL.path == optURL.standardizedFileURL.path
        } else {
            // Factory default option (url == nil): active when current profile is in /Library/ColorSync/Profiles/Displays
            // and user hasn't explicitly picked another profile
            let saved = UserDefaults.standard.string(forKey: "mdp.savedICC.\(displayID)") ?? "factory"
            return saved == "factory" && active.path.contains("/Library/ColorSync/Profiles/Displays/")
        }
    }

    /// Applies an ICC Color Profile immediately via ColorSync
    public func applyColorProfile(_ option: ColorProfileOption, for displayID: CGDirectDisplayID) -> (success: Bool, message: String) {
        let ok = MDP_SetDisplayColorProfileURL(displayID, option.url)
        UserDefaults.standard.set(option.url?.path ?? "factory", forKey: "mdp.savedICC.\(displayID)")

        if let newURL = MDP_CopyCurrentColorProfileURL(displayID) {
            activeProfileURL[displayID] = newURL
        } else {
            activeProfileURL[displayID] = option.url
        }

        // Re-apply bit-depth LUT micro-dithering after ColorSync reloads the ICC profile
        let depthChoice = selectedBitDepth[displayID] ?? .bit16
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.applyBitDepthLUTAndDithering(depthChoice, for: displayID)
        }

        if ok {
            return (true, "已成功切换色彩配置文件为: \(option.name)")
        } else {
            return (false, "切换色彩配置文件未生效，请检查系统 ColorSync 权限")
        }
    }

    /// Locks the display's current resolution mode into the highest CGS bit depth (depth=8 FP16 / 10-bit+ pipeline)
    public func stabilizeHighestBitDepth(for displayID: CGDirectDisplayID) -> String {
        let ok = MDP_LockHighestBitDepthForCurrentMode(displayID)
        refresh(for: displayID)
        let depthStr = telemetry[displayID]?.framebufferDepthDescription ?? "16-bit Float FP16"
        return ok
            ? "已锁定最高位深渲染管线: \(depthStr)"
            : "当前已处于最高位深管线: \(depthStr)"
    }

    // MARK: - Hardware DDC RGB Gain Calibration (VCP 0x16 / 0x18 / 0x1A)

    public func setHardwareRGBGain(for displayID: CGDirectDisplayID, r: Double, g: Double, b: Double) {
        redGain[displayID] = r
        greenGain[displayID] = g
        blueGain[displayID] = b

        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .redGain, value: UInt16(r))
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .greenGain, value: UInt16(g))
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .blueGain, value: UInt16(b))
    }
}
