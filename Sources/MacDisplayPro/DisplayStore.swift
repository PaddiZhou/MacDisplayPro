import Foundation
import AppKit
import CoreGraphics
import Combine
import CDisplayBridge

@MainActor
public final class DisplayStore: ObservableObject {
    public static let shared = DisplayStore()

    @Published public var displays: [ManagedDisplay] = []
    @Published public var selectedDisplayID: CGDirectDisplayID = CGMainDisplayID()
    @Published public var smartProfiles: [CGDirectDisplayID: SmartDisplayProfile] = [:]

    // Auto-Adaptation toggles
    @Published public var autoAdaptOnConnect: Bool = AutoAdaptEngine.shared.isAutoAdaptOnLaunchEnabled {
        didSet {
            AutoAdaptEngine.shared.isAutoAdaptOnLaunchEnabled = autoAdaptOnConnect
        }
    }
    @Published public var autoCircadianEnabled: Bool = AutoAdaptEngine.shared.isAutoCircadianEnabled {
        didSet {
            AutoAdaptEngine.shared.isAutoCircadianEnabled = autoCircadianEnabled
            if autoCircadianEnabled, let disp = selectedDisplay {
                applyCircadianToDisplay(disp.id)
            }
        }
    }
    @Published public var launchAtLogin: Bool = AutoAdaptEngine.shared.isLaunchAtLoginEnabled {
        didSet {
            let execPath = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "/Applications/MacDisplayPro.app/Contents/MacOS/MacDisplayPro"
            AutoAdaptEngine.shared.setLaunchAtLogin(launchAtLogin, appExecutablePath: execPath)
            statusMessage = launchAtLogin ? "已开启开机自动启动并恢复默认屏幕参数" : "已关闭开机自动启动"
        }
    }

    // Per-display DDC & Luminance state
    @Published public var ddcBrightness: [CGDirectDisplayID: Double] = [:]
    @Published public var ddcContrast: [CGDirectDisplayID: Double] = [:]
    @Published public var ddcVolume: [CGDirectDisplayID: Double] = [:]
    @Published public var ddcMuted: [CGDirectDisplayID: Bool] = [:]
    @Published public var xdrLuminanceFactor: [CGDirectDisplayID: Double] = [:]
    @Published public var warmthFactor: [CGDirectDisplayID: Double] = [:]
    @Published public var statusMessage: String = "就绪"
    @Published public var mediaKeysInterceptEnabled: Bool = false {
        didSet {
            if mediaKeysInterceptEnabled {
                startMediaKeyMonitor()
            } else {
                stopMediaKeyMonitor()
            }
        }
    }

    // Custom HiDPI Editor state & Studio UI state
    @Published public var customHiDPIPresets: [CustomHiDPIPreset] = CustomHiDPIPreset.defaultPresetsFor2K()
    @Published public var selectedTab: Int = 0
    @Published public var newHiDPIWidth: String = "2048"
    @Published public var newHiDPIHeight: String = "1152"
    @Published public var generatedPlistPreview: String = ""
    @Published public var overrideInstallAlertMessage: String = ""
    @Published public var showOverrideAlert: Bool = false

    // Custom Virtual Display input fields
    @Published public var customVirtName: String = "MacDisplayPro Custom"
    @Published public var customVirtWidth: String = "2560"
    @Published public var customVirtHeight: String = "1440"
    @Published public var customVirtHz: String = "60"
    @Published public var customVirtHiDPI: Bool = true

    // Raw VCP Debugger fields
    @Published public var customVCPHex: String = "10"
    @Published public var customVCPWriteValue: String = "92"
    @Published public var customVCPReadOutput: String = "等待读取..."

    private var eventMonitor: Any?
    private var liveSyncTimer: Timer?
    private var lastUserWriteTime: Date = .distantPast
    private var ddcPollCycle: Int = 0
    private var hasPerformedInitialAutoAdapt = false

    private init() {
        refreshDisplays()

        if autoAdaptOnConnect && !hasPerformedInitialAutoAdapt {
            hasPerformedInitialAutoAdapt = true
            performAutoAdaptAllDisplays(silent: true)
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.refreshDisplays()
                if self.autoAdaptOnConnect {
                    self.performAutoAdaptAllDisplays(silent: true)
                }
            }
        }

        // Listen for macOS ColorSync profile changes made in System Settings
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.ColorSync.DeviceNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                for disp in self.displays {
                    ColorAndHardwareEngine.shared.refresh(for: disp.id)
                }
            }
        }

        startLiveHardwareSyncTimer()
    }

    /// Periodically polls system DisplayServices brightness, ColorSync profile, resolution mode, and DDC/CI hardware state
    /// so any changes made via Apple System Settings, Control Center, keyboard, or monitor OSD sync back to the app in real time.
    private func startLiveHardwareSyncTimer() {
        liveSyncTimer?.invalidate()
        liveSyncTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollExternalAndSystemChanges()
            }
        }
    }

    private func pollExternalAndSystemChanges() {
        // Pause background polling for 2.2s while user is actively dragging sliders inside MacDisplayPro
        guard Date().timeIntervalSince(lastUserWriteTime) > 2.2 else { return }
        ddcPollCycle += 1

        for disp in displays where !disp.isVirtual {
            let id = disp.id

            // 1. Sync ColorSync ICC Profile & HDMI Link Telemetry if changed in macOS System Settings
            ColorAndHardwareEngine.shared.refresh(for: id)

            // 2. Sync Resolution / Refresh Rate if changed in macOS System Settings
            let curModeNum = MDP_GetCurrentDisplayModeNumber(id)
            if let existingMode = disp.currentMode, let existingCGS = existingMode.cgsModeNumber, existingCGS != curModeNum {
                refreshDisplays()
                return
            }

            // 3. Sync Apple Native Brightness (Built-in Retina / Apple Studio Display / DisplayServices)
            if let nativeB = DDCController.shared.getNativeBrightness(displayID: id) {
                let pct = Double((nativeB * 100.0).rounded())
                if abs((ddcBrightness[id] ?? 92.0) - pct) >= 1.0 {
                    ddcBrightness[id] = pct
                }
            } else if disp.supportsDDC {
                // 4. Sync External Monitor Hardware DDC Brightness (0x10), Contrast (0x12), Volume (0x62) in rotation
                // Reading VCP (0x01) only reads from the monitor controller and causes ZERO EEPROM write wear.
                let codeToRead: DDCCode
                switch ddcPollCycle % 3 {
                case 0: codeToRead = .brightness
                case 1: codeToRead = .contrast
                default: codeToRead = .audioVolume
                }

                DDCController.shared.readDDC(displayID: id, code: codeToRead) { [weak self] res in
                    guard res.success && res.maxValue > 0 else { return }
                    Task { @MainActor in
                        guard let self = self, Date().timeIntervalSince(self.lastUserWriteTime) > 2.2 else { return }
                        let val = Double(res.currentValue)
                        switch codeToRead {
                        case .brightness:
                            if abs((self.ddcBrightness[id] ?? 92.0) - val) >= 1.0 {
                                self.ddcBrightness[id] = val
                            }
                        case .contrast:
                            if abs((self.ddcContrast[id] ?? 72.0) - val) >= 1.0 {
                                self.ddcContrast[id] = val
                            }
                        case .audioVolume:
                            if abs((self.ddcVolume[id] ?? 50.0) - val) >= 1.0 {
                                self.ddcVolume[id] = val
                            }
                        default:
                            break
                        }
                    }
                }
            }
        }
    }

    public var selectedDisplay: ManagedDisplay? {
        displays.first(where: { $0.id == selectedDisplayID }) ?? displays.first
    }

    public var selectedSmartProfile: SmartDisplayProfile? {
        guard let disp = selectedDisplay else { return nil }
        return smartProfiles[disp.id]
    }

    public func refreshDisplays() {
        let screens = NSScreen.screens
        var newDisplays: [ManagedDisplay] = []
        var newProfiles: [CGDirectDisplayID: SmartDisplayProfile] = [:]
        let virtualIDs = Set(VirtualDisplayManager.shared.activeVirtualDisplays.map { $0.displayID })

        for screen in screens {
            let id = screen.displayID
            guard id != 0 else { continue }

            let name = screen.localizedName
            let vendor = CGDisplayVendorNumber(id)
            let model = CGDisplayModelNumber(id)
            let serial = CGDisplaySerialNumber(id)
            let builtin = CGDisplayIsBuiltin(id) != 0
            let isVirt = virtualIDs.contains(id) || vendor == 0xF0F0

            let (ddcSupported, adapterName) = DDCController.shared.probeDisplay(id)
            let maxEDR = screen.maximumPotentialExtendedDynamicRangeColorComponentValue
            let curEDR = screen.maximumExtendedDynamicRangeColorComponentValue

            let (currentMode, hiDPI, loDPI) = HiDPIManager.shared.fetchModes(for: id)

            let disp = ManagedDisplay(
                id: id,
                name: name,
                vendorID: vendor,
                modelID: model,
                serialNumber: serial,
                isBuiltin: builtin,
                isVirtual: isVirt,
                supportsDDC: ddcSupported,
                ddcAdapterName: adapterName,
                maxPotentialEDR: maxEDR,
                currentEDRHeadroom: curEDR,
                currentMode: currentMode,
                hiDPIModes: hiDPI,
                loDPIModes: loDPI
            )
            newDisplays.append(disp)

            let profile = AutoAdaptEngine.shared.analyzeDisplay(disp)
            newProfiles[id] = profile
            ColorAndHardwareEngine.shared.refresh(for: id)

            // Initialize state defaults if not yet populated
            if ddcBrightness[id] == nil {
                if let nativeB = DDCController.shared.getNativeBrightness(displayID: id) {
                    ddcBrightness[id] = Double(nativeB * 100.0)
                } else {
                    ddcBrightness[id] = profile.recommendedBrightness
                    if ddcSupported {
                        DDCController.shared.readDDC(displayID: id, code: .brightness) { [weak self] res in
                            if res.success && res.maxValue > 0 {
                                Task { @MainActor in
                                    self?.ddcBrightness[id] = Double(res.currentValue)
                                }
                            }
                        }
                    }
                }
            }
            if ddcContrast[id] == nil {
                ddcContrast[id] = 70.0
                if ddcSupported {
                    DDCController.shared.readDDC(displayID: id, code: .contrast) { [weak self] res in
                        if res.success && res.maxValue > 0 {
                            Task { @MainActor in
                                self?.ddcContrast[id] = Double(res.currentValue)
                            }
                        }
                    }
                }
            }
            if ddcVolume[id] == nil {
                ddcVolume[id] = 50.0
                if ddcSupported {
                    DDCController.shared.readDDC(displayID: id, code: .audioVolume) { [weak self] res in
                        if res.success && res.maxValue > 0 {
                            Task { @MainActor in
                                self?.ddcVolume[id] = Double(res.currentValue)
                            }
                        }
                    }
                }
            }
            if ddcMuted[id] == nil { ddcMuted[id] = false }
            if xdrLuminanceFactor[id] == nil { xdrLuminanceFactor[id] = 1.0 }
            if warmthFactor[id] == nil { warmthFactor[id] = 0.0 }
        }

        self.displays = newDisplays
        self.smartProfiles = newProfiles

        if !newDisplays.contains(where: { $0.id == selectedDisplayID }), let first = newDisplays.first {
            selectedDisplayID = first.id
        }

        if let prof = selectedSmartProfile {
            customHiDPIPresets = prof.tailoredHiDPIPresets
        }
    }

    // MARK: - Smart Auto-Adaptation Engine

    /// Automatically adapts all connected displays (or on hotplug)
    public func performAutoAdaptAllDisplays(silent: Bool = false) {
        var adaptedCount = 0
        for disp in displays where !disp.isVirtual {
            if disp.supportsDDC && !mediaKeysInterceptEnabled {
                mediaKeysInterceptEnabled = true
            }
            if let profile = smartProfiles[disp.id] {
                // Ensure Pure RGB 4:4:4 Full Range link is preserved in SDR mode if macOS System Settings reset it to [2] YCbCr Limited Range
                if !disp.isBuiltin && ColorAndHardwareEngine.shared.userSelectedHDR12Bit[disp.id] != true {
                    let tel = MDP_GetDisplayHardwareTelemetry(disp.id)
                    if tel.activeEOTF == 0 && (tel.activePixelEncoding != 0 || tel.activeDynamicRange != 1) {
                        _ = MDP_ForceRGB444FullRangeLink(disp.id)
                        ColorAndHardwareEngine.shared.refresh(for: disp.id)
                    }
                }
                // 1. Check if user previously saved a preferred mode for this monitor
                if let savedModeID = AutoAdaptEngine.shared.loadUserResolutionPreference(displayKey: profile.displayIdentifierKey),
                   let matched = (disp.hiDPIModes + disp.loDPIModes).first(where: { $0.id == savedModeID }),
                   !matched.isCurrent {
                    _ = HiDPIManager.shared.applyResolutionMode(matched)
                    adaptedCount += 1
                } else if !silent, let recMode = profile.recommendedMode, !recMode.isCurrent {
                    // When explicitly triggered by user, apply recommended golden HiDPI mode & max refresh rate
                    _ = HiDPIManager.shared.applyResolutionMode(recMode)
                    adaptedCount += 1
                }

                // 2. Apply circadian brightness/warmth if enabled
                if autoCircadianEnabled {
                    applyCircadianToDisplay(disp.id)
                }
            }
        }
        if !silent {
            refreshDisplays()
            statusMessage = "智能自动适配完成：已优化最佳 HiDPI 分辨率、最高刷新率、DDC 硬件通道与键盘联动"
        }
    }

    /// One-click Smart Auto-Adaptation for a specific display
    public func performSmartAutoAdapt(for displayID: CGDirectDisplayID) {
        guard let disp = displays.first(where: { $0.id == displayID }),
              let profile = smartProfiles[displayID] else { return }

        // 1. Tailor Custom HiDPI presets to match panel's exact aspect ratio
        customHiDPIPresets = profile.tailoredHiDPIPresets

        // 2. Enable media key forwarding if external display
        if !disp.isBuiltin && !mediaKeysInterceptEnabled {
            mediaKeysInterceptEnabled = true
        }

        // 3. Apply optimal HiDPI resolution & highest refresh rate (or Zero-Reboot Virtual HiDPI Mirror if needed)
        var modeResultText = ""
        if let recMode = profile.recommendedMode {
            if !recMode.isCurrent {
                if HiDPIManager.shared.applyResolutionMode(recMode) {
                    AutoAdaptEngine.shared.saveUserResolutionPreference(displayKey: profile.displayIdentifierKey, modeID: recMode.id)
                    modeResultText = "已切换至最佳模式 \(recMode.resolutionText) @ \(recMode.refreshRateText) (\(recMode.isHiDPI ? "HiDPI 2x" : "原生"))"
                }
            } else {
                modeResultText = "当前已处于最佳模式 \(recMode.resolutionText) @ \(recMode.refreshRateText)"
            }
        }

        // If monitor is 2K / Ultrawide and has ZERO HiDPI modes available in macOS, automatically activate Zero-Reboot HiDPI Mirror
        if disp.hiDPIModes.isEmpty && profile.needsZeroRebootHiDPIMirror && !disp.isVirtual {
            let targetW = UInt32(profile.tailoredHiDPIPresets.first?.scaledWidth ?? profile.nativeWidth)
            let targetH = UInt32(profile.tailoredHiDPIPresets.first?.scaledHeight ?? profile.nativeHeight)
            if VirtualDisplayManager.shared.enableZeroRebootHiDPIMirror(
                forPhysicalDisplay: disp.id,
                physicalName: disp.name,
                targetScaledWidth: targetW,
                targetScaledHeight: targetH,
                refreshRate: profile.maxRefreshRate
            ) {
                modeResultText = "检测到无原生 HiDPI，已自动启用 \(targetW)×\(targetH) 零重启 2x HiDPI 镜像！"
            }
        }

        // 4. Sync circadian luminance if enabled
        if autoCircadianEnabled {
            applyCircadianToDisplay(displayID)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.refreshDisplays()
            self?.statusMessage = "已自动适配【\(disp.name)】：\(modeResultText)"
        }
    }

    public func lockCurrentAsDefault(for displayID: CGDirectDisplayID) {
        guard let disp = displays.first(where: { $0.id == displayID }) else { return }
        statusMessage = AutoAdaptEngine.shared.lockCurrentDisplayStateAsDefault(disp)
        HUDManager.shared.show(
            icon: "pin.fill",
            title: "已锁定为永久默认配置",
            subtitle: disp.currentMode?.resolutionText ?? "2048×1152 HiDPI",
            progress: nil,
            tint: .green
        )
    }

    public func applySmartScene(_ scene: SmartScenePreset, for displayID: CGDirectDisplayID) {
        guard let disp = displays.first(where: { $0.id == displayID }) else { return }

        // 1. Switch to scene's target HiDPI resolution if not already active
        if let targetMode = disp.hiDPIModes.first(where: { abs($0.width - scene.targetWidth) <= 16 }), !targetMode.isCurrent {
            _ = HiDPIManager.shared.applyResolutionMode(targetMode)
        }

        // 2. Apply DDC brightness & contrast
        setHardwareBrightness(for: displayID, value: scene.brightness)
        setHardwareContrast(for: displayID, value: scene.contrast)

        // 3. Apply XDR boost / dimming & warmth
        setXDRLuminance(for: displayID, factor: scene.xdrFactor)
        setWarmth(for: displayID, warmth: scene.warmth)

        // 4. Apply DDC hardware RGB gain
        ColorAndHardwareEngine.shared.setHardwareRGBGain(
            for: displayID,
            r: scene.rgbGain.0,
            g: scene.rgbGain.1,
            b: scene.rgbGain.2
        )

        // 5. Apply ICC profile if specified
        if let keyword = scene.iccKeyword,
           let prof = ColorAndHardwareEngine.shared.availableProfiles.first(where: { $0.name.localizedCaseInsensitiveContains(keyword) }) {
            _ = ColorAndHardwareEngine.shared.applyColorProfile(prof, for: displayID)
        }

        // 6. Ensure highest 16-bit FP16 bit depth
        _ = ColorAndHardwareEngine.shared.stabilizeHighestBitDepth(for: displayID)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshDisplays()
            self?.statusMessage = "已激活情景模式：【\(scene.title)】"
            HUDManager.shared.show(
                icon: scene.icon,
                title: scene.title,
                subtitle: "\(scene.targetWidth) HiDPI • 亮度 \(Int(scene.brightness))%",
                progress: scene.brightness / 100.0,
                tint: scene.tint
            )
        }
    }

    private func applyCircadianToDisplay(_ displayID: CGDirectDisplayID) {
        let (recB, recW) = AutoAdaptEngine.shared.computeCircadianLuminance()
        setHardwareBrightness(for: displayID, value: recB)
        setWarmth(for: displayID, warmth: recW)
    }

    // MARK: - Actions

    public func setHardwareBrightness(for displayID: CGDirectDisplayID, value: Double) {
        lastUserWriteTime = Date()
        let clamped = max(0.0, min(100.0, value))
        ddcBrightness[displayID] = clamped
        HUDManager.shared.show(
            icon: "sun.max.fill",
            title: "硬件亮度",
            subtitle: "\(Int(clamped))%",
            progress: clamped / 100.0,
            tint: .yellow
        )

        if DDCController.shared.setNativeBrightness(displayID: displayID, brightness: Float(clamped / 100.0)) {
            statusMessage = "已设置原生屏幕亮度: \(Int(clamped))%"
            return
        }

        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .brightness, value: UInt16(clamped)) { [weak self] ok in
            Task { @MainActor in
                if ok {
                    self?.statusMessage = "DDC/CI 硬件亮度 (0x10) 已更新: \(Int(clamped))%"
                } else {
                    let factor = Float(max(0.15, clamped / 100.0))
                    DDCController.shared.applyGammaGain(displayID: displayID, brightnessFactor: factor)
                    self?.statusMessage = "已通过硬件 LUT Gamma 同步亮度: \(Int(clamped))%"
                }
            }
        }
    }

    public func setHardwareContrast(for displayID: CGDirectDisplayID, value: Double) {
        lastUserWriteTime = Date()
        let clamped = max(0.0, min(100.0, value))
        ddcContrast[displayID] = clamped
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .contrast, value: UInt16(clamped)) { [weak self] ok in
            Task { @MainActor in
                self?.statusMessage = ok
                    ? "DDC/CI 硬件对比度 (0x12) 已更新: \(Int(clamped))%"
                    : "已发送对比度指令 (0x12): \(Int(clamped))%"
            }
        }
    }

    public func setHardwareVolume(for displayID: CGDirectDisplayID, value: Double) {
        lastUserWriteTime = Date()
        let clamped = max(0.0, min(100.0, value))
        ddcVolume[displayID] = clamped
        HUDManager.shared.show(
            icon: clamped < 1 ? "speaker.slash.fill" : "speaker.wave.2.fill",
            title: "显示器音量",
            subtitle: "\(Int(clamped))%",
            progress: clamped / 100.0,
            tint: .blue
        )
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .audioVolume, value: UInt16(clamped)) { [weak self] ok in
            Task { @MainActor in
                self?.statusMessage = ok
                    ? "DDC/CI 显示器音量 (0x62) 已更新: \(Int(clamped))%"
                    : "已发送显示器音量指令 (0x62): \(Int(clamped))%"
            }
        }
    }

    public func toggleHardwareMute(for displayID: CGDirectDisplayID) {
        let newMuted = !(ddcMuted[displayID] ?? false)
        ddcMuted[displayID] = newMuted
        let vcpVal: UInt16 = newMuted ? 1 : 2
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .audioMute, value: vcpVal) { [weak self] _ in
            Task { @MainActor in
                self?.statusMessage = newMuted ? "已静音显示器扬声器 (0x8D=1)" : "已取消显示器静音 (0x8D=2)"
            }
        }
    }

    public func switchInputSource(for displayID: CGDirectDisplayID, input: DDCInputSource) {
        DDCController.shared.writeDDCDebounced(displayID: displayID, code: .inputSource, value: input.rawValue) { [weak self] _ in
            Task { @MainActor in
                self?.statusMessage = "已向显示器发送输入源切换指令: \(input.label)"
            }
        }
    }

    public func setXDRLuminance(for displayID: CGDirectDisplayID, factor: Double) {
        let clamped = max(0.08, min(2.50, factor))
        xdrLuminanceFactor[displayID] = clamped
        let w = Float(warmthFactor[displayID] ?? 0.0)
        XDRBrightnessEngine.shared.setLuminance(for: displayID, factor: Float(clamped), warmth: w)

        if clamped > 1.01 {
            let estimatedNits = Int((500.0 + (clamped - 1.0) / 1.5 * 1100.0).rounded())
            statusMessage = "XDR 极限提亮已激活: \(Int(clamped * 100))% (峰值约 \(estimatedNits) nits)"
        } else if clamped < 0.99 {
            statusMessage = "软件暗光遮罩已启用: \(Int(clamped * 100))%"
        } else {
            statusMessage = "已恢复标准 100% SDR 亮度"
        }
    }

    public func setWarmth(for displayID: CGDirectDisplayID, warmth: Double) {
        let clamped = max(0.0, min(1.0, warmth))
        warmthFactor[displayID] = clamped
        let f = Float(xdrLuminanceFactor[displayID] ?? 1.0)
        XDRBrightnessEngine.shared.setLuminance(for: displayID, factor: f, warmth: Float(clamped))
        statusMessage = "护眼色温调节: \(Int(clamped * 100))%"
    }

    public func switchResolution(_ mode: DisplayResolutionMode) {
        if HiDPIManager.shared.applyResolutionMode(mode) {
            if let prof = smartProfiles[mode.displayID] {
                AutoAdaptEngine.shared.saveUserResolutionPreference(displayKey: prof.displayIdentifierKey, modeID: mode.id)
            }
            statusMessage = "已切换分辨率至 \(mode.resolutionText) @ \(mode.refreshRateText) (\(mode.isHiDPI ? "HiDPI" : "LoDPI"))"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.refreshDisplays()
            }
        } else {
            statusMessage = "切换分辨率失败，该模式可能需要 HiDPI Override 或虚拟屏镜像"
        }
    }

    // MARK: - Media Key (Keyboard Brightness/Volume) Listener
    private func startMediaKeyMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .systemDefined) { [weak self] event in
            guard event.subtype.rawValue == 8 else { return }
            let data1 = event.data1
            let keyCode = (data1 & 0xFFFF0000) >> 16
            let keyFlags = (data1 & 0x0000FFFF)
            let keyState = ((keyFlags & 0xFF00) >> 8) == 0xA

            guard keyState else { return }
            Task { @MainActor in
                guard let self = self, let disp = self.selectedDisplay else { return }
                switch keyCode {
                case 2:
                    let cur = self.ddcBrightness[disp.id] ?? 75
                    self.setHardwareBrightness(for: disp.id, value: min(100, cur + 6.25))
                case 3:
                    let cur = self.ddcBrightness[disp.id] ?? 75
                    self.setHardwareBrightness(for: disp.id, value: max(0, cur - 6.25))
                case 0:
                    let cur = self.ddcVolume[disp.id] ?? 50
                    self.setHardwareVolume(for: disp.id, value: min(100, cur + 6.25))
                case 1:
                    let cur = self.ddcVolume[disp.id] ?? 50
                    self.setHardwareVolume(for: disp.id, value: max(0, cur - 6.25))
                case 7:
                    self.toggleHardwareMute(for: disp.id)
                default:
                    break
                }
            }
        }
        statusMessage = "已开启键盘亮度/音量键联动外接显示器"
    }

    private func stopMediaKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
        statusMessage = "已关闭键盘媒体键接管"
    }
}
