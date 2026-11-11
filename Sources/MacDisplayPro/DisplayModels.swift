import Foundation
import CoreGraphics
import AppKit
import CDisplayBridge

// MARK: - VCP Codes (DDC/CI Standard)
public enum DDCCode: UInt8, CaseIterable, Identifiable {
    case brightness = 0x10
    case contrast = 0x12
    case redGain = 0x16
    case greenGain = 0x18
    case blueGain = 0x1A
    case inputSource = 0x60
    case audioVolume = 0x62
    case audioMute = 0x8D
    case powerMode = 0xD6

    public var id: UInt8 { rawValue }

    public var title: String {
        switch self {
        case .brightness: return "硬件亮度 (0x10)"
        case .contrast: return "硬件对比度 (0x12)"
        case .redGain: return "红色增益 (0x16)"
        case .greenGain: return "绿色增益 (0x18)"
        case .blueGain: return "蓝色增益 (0x1A)"
        case .inputSource: return "输入信号源 (0x60)"
        case .audioVolume: return "显示器音量 (0x62)"
        case .audioMute: return "静音控制 (0x8D)"
        case .powerMode: return "电源状态 (0xD6)"
        }
    }
}

public enum DDCInputSource: UInt16, CaseIterable, Identifiable {
    case displayPort1 = 0x0F
    case displayPort2 = 0x10
    case hdmi1 = 0x11
    case hdmi2 = 0x12
    case usbC = 0x1B

    public var id: UInt16 { rawValue }

    public var label: String {
        switch self {
        case .displayPort1: return "DP 1 (0x0F)"
        case .displayPort2: return "DP 2 (0x10)"
        case .hdmi1: return "HDMI 1 (0x11)"
        case .hdmi2: return "HDMI 2 (0x12)"
        case .usbC: return "USB-C / Thunderbolt (0x1B)"
        }
    }
}

// MARK: - Resolution Mode Model
public struct DisplayResolutionMode: Identifiable, Hashable {
    public let id: String
    public let displayID: CGDirectDisplayID
    public let width: Int
    public let height: Int
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let refreshRate: Double
    public let isHiDPI: Bool
    public let isCurrent: Bool
    public let cgsModeNumber: Int32?
    public let cgDisplayMode: CGDisplayMode?

    public var resolutionText: String {
        "\(width) × \(height)"
    }

    public var backingResolutionText: String {
        if isHiDPI && (pixelWidth != width || pixelHeight != height) {
            return "渲染 \(pixelWidth)×\(pixelHeight) (2x Retina)"
        }
        return "原生 1x (\(pixelWidth)×\(pixelHeight))"
    }

    public var refreshRateText: String {
        let rounded = Int(refreshRate.rounded())
        return "\(rounded > 0 ? rounded : 60) Hz"
    }

    public var aspectRatioText: String {
        guard height > 0 else { return "" }
        let ratio = Double(width) / Double(height)
        if abs(ratio - 16.0/9.0) < 0.04 { return "16:9" }
        if abs(ratio - 16.0/10.0) < 0.04 { return "16:10" }
        if abs(ratio - 21.0/9.0) < 0.08 { return "21:9" }
        if abs(ratio - 32.0/9.0) < 0.08 { return "32:9" }
        if abs(ratio - 4.0/3.0) < 0.04 { return "4:3" }
        return String(format: "%.2f:1", ratio)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: DisplayResolutionMode, rhs: DisplayResolutionMode) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Custom HiDPI Scale Preset
public struct CustomHiDPIPreset: Identifiable, Hashable {
    public let id = UUID()
    public var scaledWidth: Int
    public var scaledHeight: Int
    public var label: String
    public var enabled: Bool

    public static func defaultPresetsFor2K() -> [CustomHiDPIPreset] {
        [
            CustomHiDPIPreset(scaledWidth: 2560, scaledHeight: 1440, label: "2560 × 1440 (原生尺寸 2x HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 2304, scaledHeight: 1296, label: "2304 × 1296 (黄金比例 2K HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 2048, scaledHeight: 1152, label: "2048 × 1152 (最舒适字体 2K HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 1920, scaledHeight: 1080, label: "1920 × 1080 (1080p 超清 HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 1600, scaledHeight: 900,  label: "1600 × 900 (大字体 HiDPI)", enabled: false)
        ]
    }

    public static func defaultPresetsForUltrawide() -> [CustomHiDPIPreset] {
        [
            CustomHiDPIPreset(scaledWidth: 3440, scaledHeight: 1440, label: "3440 × 1440 (带鱼屏全尺寸 HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 3008, scaledHeight: 1260, label: "3008 × 1260 (带鱼屏黄金缩放 HiDPI)", enabled: true),
            CustomHiDPIPreset(scaledWidth: 2752, scaledHeight: 1152, label: "2752 × 1152 (带鱼屏舒适字体 HiDPI)", enabled: true)
        ]
    }
}

// MARK: - Virtual Display Preset
public struct VirtualDisplayTemplate: Identifiable {
    public let id = UUID()
    public let title: String
    public let subtitle: String
    public let baseWidth: UInt32
    public let baseHeight: UInt32
    public let refreshRate: Double
    public let hiDPI: Bool

    public static let templates: [VirtualDisplayTemplate] = [
        VirtualDisplayTemplate(title: "2K QHD Retina 虚拟屏", subtitle: "2560×1440 (5120×2880 HiDPI) @ 60Hz", baseWidth: 2560, baseHeight: 1440, refreshRate: 60, hiDPI: true),
        VirtualDisplayTemplate(title: "4K UHD Studio 虚拟屏", subtitle: "3840×2160 (HiDPI) @ 60Hz", baseWidth: 3840, baseHeight: 2160, refreshRate: 60, hiDPI: true),
        VirtualDisplayTemplate(title: "1080p 高刷电竞虚拟屏", subtitle: "1920×1080 (HiDPI) @ 120Hz", baseWidth: 1920, baseHeight: 1080, refreshRate: 120, hiDPI: true),
        VirtualDisplayTemplate(title: "21:9 带鱼屏虚拟显示器", subtitle: "3440×1440 (HiDPI) @ 60Hz", baseWidth: 3440, baseHeight: 1440, refreshRate: 60, hiDPI: true),
        VirtualDisplayTemplate(title: "iPad Pro 4:3 随航扩展屏", subtitle: "2048×1536 (HiDPI) @ 60Hz", baseWidth: 2048, baseHeight: 1536, refreshRate: 60, hiDPI: true)
    ]
}

// MARK: - Managed Display Info
public struct ManagedDisplay: Identifiable {
    public let id: CGDirectDisplayID
    public let name: String
    public let vendorID: UInt32
    public let modelID: UInt32
    public let serialNumber: UInt32
    public let isBuiltin: Bool
    public let isVirtual: Bool
    public let supportsDDC: Bool
    public let ddcAdapterName: String
    public let maxPotentialEDR: CGFloat
    public let currentEDRHeadroom: CGFloat
    public let currentMode: DisplayResolutionMode?
    public let hiDPIModes: [DisplayResolutionMode]
    public let loDPIModes: [DisplayResolutionMode]

    public var vendorHex: String {
        String(format: "0x%04X", vendorID)
    }

    public var modelHex: String {
        String(format: "0x%04X", modelID)
    }

    public var supportsXDRBoost: Bool {
        maxPotentialEDR > 1.05
    }
}
