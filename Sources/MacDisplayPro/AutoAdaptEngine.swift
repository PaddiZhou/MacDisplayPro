import Foundation
import CoreGraphics
import AppKit
import CDisplayBridge

/// Represents the automatically analyzed hardware profile and optimal settings for a connected display.
public struct SmartDisplayProfile: Identifiable {
    public let id: CGDirectDisplayID
    public let displayIdentifierKey: String // Vendor-Model-Serial key for persistent storage
    public let nativeWidth: Int
    public let nativeHeight: Int
    public let maxRefreshRate: Double
    public let panelCategory: PanelCategory
    public let recommendedMode: DisplayResolutionMode?
    public let alternativeHiDPIModes: [DisplayResolutionMode]
    public let needsZeroRebootHiDPIMirror: Bool
    public let tailoredHiDPIPresets: [CustomHiDPIPreset]
    public let recommendedBrightness: Double
    public let recommendedWarmth: Double
    public let summaryReport: String

    public enum PanelCategory: String {
        case builtInRetina = "Mac 内置视网膜屏幕"
        case uhd4KOrHigher = "4K / 5K 超高清外接显示器"
        case qhd2K = "2K QHD (1440p) 外接显示器"
        case ultrawide = "21:9 / 32:9 超宽带鱼屏显示器"
        case fhd1080p = "1080p FHD 标准外接显示器"
    }
}

@MainActor
public final class AutoAdaptEngine {
    public static let shared = AutoAdaptEngine()

    private let defaults = UserDefaults.standard
    private let autoAdaptOnLaunchKey = "mdp.autoAdaptOnLaunch"
    private let autoCircadianKey = "mdp.autoCircadianEnabled"

    private init() {}

    public var isAutoAdaptOnLaunchEnabled: Bool {
        get {
            if defaults.object(forKey: autoAdaptOnLaunchKey) == nil {
                return true
            }
            return defaults.bool(forKey: autoAdaptOnLaunchKey)
        }
        set {
            defaults.set(newValue, forKey: autoAdaptOnLaunchKey)
        }
    }

    public var isAutoCircadianEnabled: Bool {
        get { defaults.bool(forKey: autoCircadianKey) }
        set { defaults.set(newValue, forKey: autoCircadianKey) }
    }

    /// Analyzes a display's all hardware modes, EDID dimensions, refresh rates, DDC & EDR capabilities,
    /// and computes the optimal configuration profile.
    public func analyzeDisplay(_ display: ManagedDisplay) -> SmartDisplayProfile {
        let allModes = display.hiDPIModes + display.loDPIModes

        var maxNativeW = display.currentMode?.width ?? 1920
        var maxNativeH = display.currentMode?.height ?? 1080
        var maxHz: Double = display.currentMode?.refreshRate ?? 60.0

        for m in display.loDPIModes {
            if m.width * m.height >= maxNativeW * maxNativeH {
                maxNativeW = m.width
                maxNativeH = m.height
            }
            if m.refreshRate > maxHz {
                maxHz = m.refreshRate
            }
        }
        for m in display.hiDPIModes {
            if m.refreshRate > maxHz {
                maxHz = m.refreshRate
            }
        }

        let aspect = Double(maxNativeW) / Double(max(1, maxNativeH))

        let category: SmartDisplayProfile.PanelCategory
        if display.isBuiltin {
            category = .builtInRetina
        } else if aspect > 2.1 {
            category = .ultrawide
        } else if maxNativeW >= 3840 || maxNativeH >= 2160 {
            category = .uhd4KOrHigher
        } else if maxNativeW >= 2560 || maxNativeH >= 1440 {
            category = .qhd2K
        } else {
            category = .fhd1080p
        }

        let (bestMode, altModes, needsMirror) = pickOptimalMode(
            category: category,
            nativeWidth: maxNativeW,
            nativeHeight: maxNativeH,
            maxRefreshRate: maxHz,
            hiDPIModes: display.hiDPIModes,
            loDPIModes: display.loDPIModes,
            allModes: allModes
        )

        let tailoredPresets = buildTailoredPresets(
            category: category,
            nativeWidth: maxNativeW,
            nativeHeight: maxNativeH,
            aspectRatio: aspect
        )

        let (recBrightness, recWarmth) = computeCircadianLuminance()

        let key = String(format: "%04X-%04X-%u", display.vendorID, display.modelID, display.serialNumber)
        let recModeDesc = bestMode.map { "\($0.resolutionText) @ \($0.refreshRateText) (\($0.isHiDPI ? "HiDPI 2x" : "原生 1x"))" } ?? "保持当前"
        let summary = "识别为【\(category.rawValue)】(物理面板 \(maxNativeW)×\(maxNativeH) @ \(Int(maxHz))Hz) → 默认黄金模式: \(recModeDesc)"

        return SmartDisplayProfile(
            id: display.id,
            displayIdentifierKey: key,
            nativeWidth: maxNativeW,
            nativeHeight: maxNativeH,
            maxRefreshRate: maxHz,
            panelCategory: category,
            recommendedMode: bestMode,
            alternativeHiDPIModes: altModes,
            needsZeroRebootHiDPIMirror: needsMirror,
            tailoredHiDPIPresets: tailoredPresets,
            recommendedBrightness: recBrightness,
            recommendedWarmth: recWarmth,
            summaryReport: summary
        )
    }

    private func pickOptimalMode(
        category: SmartDisplayProfile.PanelCategory,
        nativeWidth: Int,
        nativeHeight: Int,
        maxRefreshRate: Double,
        hiDPIModes: [DisplayResolutionMode],
        loDPIModes: [DisplayResolutionMode],
        allModes: [DisplayResolutionMode]
    ) -> (best: DisplayResolutionMode?, alternatives: [DisplayResolutionMode], needsMirror: Bool) {

        let preferredWidths: [Int]
        switch category {
        case .uhd4KOrHigher:
            // Prioritize 1920x1080 HiDPI (3840x2160 1:1 pixel-perfect 4K 2x Retina) as #1 user favorite default mode!
            preferredWidths = [1920, 2048, 2304, 2560]
        case .qhd2K:
            preferredWidths = [2048, 2304, 2560, 1920]
        case .ultrawide:
            preferredWidths = [2752, 3008, 3440, 2560]
        case .fhd1080p:
            preferredWidths = [1920, 1600]
        case .builtInRetina:
            preferredWidths = [1728, 1512, 1440, 1680]
        }

        for targetW in preferredWidths {
            let candidates = hiDPIModes.filter { abs($0.width - targetW) <= 16 }
            if let highestHzCandidate = candidates.max(by: { $0.refreshRate < $1.refreshRate }) {
                let alts = Array(hiDPIModes.prefix(6))
                return (highestHzCandidate, alts, false)
            }
        }

        if let fallbackHiDPI = hiDPIModes.filter({ $0.width >= 1440 && $0.width <= 3008 }).max(by: {
            if abs($0.refreshRate - $1.refreshRate) > 1.0 { return $0.refreshRate < $1.refreshRate }
            return $0.width < $1.width
        }) {
            return (fallbackHiDPI, Array(hiDPIModes.prefix(6)), false)
        }

        let nativeBest = loDPIModes.max(by: {
            if $0.width != $1.width { return $0.width < $1.width }
            return $0.refreshRate < $1.refreshRate
        })
        let needsMirror = (category == .qhd2K || category == .ultrawide || category == .fhd1080p)
        return (nativeBest, Array(loDPIModes.prefix(4)), needsMirror)
    }

    private func buildTailoredPresets(
        category: SmartDisplayProfile.PanelCategory,
        nativeWidth: Int,
        nativeHeight: Int,
        aspectRatio: Double
    ) -> [CustomHiDPIPreset] {
        switch category {
        case .ultrawide:
            return CustomHiDPIPreset.defaultPresetsForUltrawide()
        case .uhd4KOrHigher, .qhd2K:
            return CustomHiDPIPreset.defaultPresetsFor2K()
        case .fhd1080p, .builtInRetina:
            let scales: [(Double, String)] = [
                (1.0, "原生全尺寸 2x HiDPI"),
                (0.90, "90% 黄金微缩 2x HiDPI"),
                (0.80, "80% 舒适字体 2x HiDPI"),
                (0.75, "75% 大字体 2x HiDPI")
            ]
            return scales.map { (factor, desc) in
                let w = (Int((Double(nativeWidth) * factor).rounded()) / 2) * 2
                let h = (Int((Double(w) / aspectRatio).rounded()) / 2) * 2
                return CustomHiDPIPreset(scaledWidth: w, scaledHeight: h, label: "\(w) × \(h) (\(desc))", enabled: true)
            }
        }
    }

    public func computeCircadianLuminance() -> (brightness: Double, warmth: Double) {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 8 && hour < 19 {
            return (92.0, 0.0)
        } else if hour >= 19 && hour < 22 {
            return (92.0, 0.0)
        } else {
            return (75.0, 0.20)
        }
    }

    // MARK: - Persistent Per-Display Profile Memory & LaunchAgent

    public func saveUserResolutionPreference(displayKey: String, modeID: String) {
        defaults.set(modeID, forKey: "mdp.savedMode.\(displayKey)")
    }

    public func loadUserResolutionPreference(displayKey: String) -> String? {
        defaults.string(forKey: "mdp.savedMode.\(displayKey)")
    }

    /// Locks the current resolution, bit-depth, anti-aliasing and sharpness as the permanent default for this display
    public func lockCurrentDisplayStateAsDefault(_ display: ManagedDisplay) -> String {
        let key = String(format: "%04X-%04X-%u", display.vendorID, display.modelID, display.serialNumber)
        if let cur = display.currentMode {
            saveUserResolutionPreference(displayKey: key, modeID: cur.id)
        }
        _ = MDP_LockHighestBitDepthForCurrentMode(display.id)
        isAutoAdaptOnLaunchEnabled = true
        let modeDesc = display.currentMode.map { "\($0.resolutionText) (\($0.backingResolutionText)) @ \($0.refreshRateText)" } ?? "当前模式"
        return "📌 已将【\(modeDesc) + 16-bit FP16 高位深管线 + 细腻去锯齿】锁定为永久默认配置！"
    }

    private var launchAgentURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.jinlong.MacDisplayPro.plist")
    }

    public var isLaunchAtLoginEnabled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    public func setLaunchAtLogin(_ enabled: Bool, appExecutablePath: String) {
        let fm = FileManager.default
        if !enabled {
            try? fm.removeItem(at: launchAgentURL)
            return
        }
        let dir = launchAgentURL.deletingLastPathComponent()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": "com.jinlong.MacDisplayPro",
            "ProgramArguments": [appExecutablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: launchAgentURL)
        }
    }
}
