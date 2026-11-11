import Foundation
import CoreGraphics
import AppKit
import CDisplayBridge

public final class HiDPIManager {
    public static let shared = HiDPIManager()

    private init() {}

    /// Enumerates all genuine CoreGraphics display modes with strict @2x Retina backing store verification (`pixelWidth >= width * 2`)
    public func fetchModes(for displayID: CGDirectDisplayID) -> (current: DisplayResolutionMode?, hiDPI: [DisplayResolutionMode], loDPI: [DisplayResolutionMode]) {
        let currentCGMode = CGDisplayCopyDisplayMode(displayID)

        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes as String: kCFBooleanTrue!] as CFDictionary
        let rawModes = (CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode]) ?? []

        var seenKeys = Set<String>()
        var hiDPIList: [DisplayResolutionMode] = []
        var loDPIList: [DisplayResolutionMode] = []
        var activeMode: DisplayResolutionMode? = nil

        for mode in rawModes {
            guard mode.isUsableForDesktopGUI() else { continue }
            let w = mode.width
            let h = mode.height
            let pw = mode.pixelWidth
            let ph = mode.pixelHeight
            let rate = mode.refreshRate > 0 ? mode.refreshRate : 60.0

            // Strict 2x Retina Backing Framebuffer verification:
            // Only classify as HiDPI when the backing pixel buffer is genuinely 2x (prevents 1x LoDPI modes from causing jagged icons!)
            let isGenuineHiDPI = (pw >= w * 2 && ph >= h * 2)
            let roundedRate = Int(rate.rounded())

            // Filter out tiny modes
            if w < 1024 || h < 640 { continue }

            let key = "\(w)x\(h)-\(pw)x\(ph)-\(roundedRate)-\(isGenuineHiDPI ? "HiDPI" : "LoDPI")"
            if seenKeys.contains(key) { continue }
            seenKeys.insert(key)

            let isCurrent = (currentCGMode?.ioDisplayModeID == mode.ioDisplayModeID)
            let item = DisplayResolutionMode(
                id: key,
                displayID: displayID,
                width: w,
                height: h,
                pixelWidth: pw,
                pixelHeight: ph,
                refreshRate: rate,
                isHiDPI: isGenuineHiDPI,
                isCurrent: isCurrent,
                cgsModeNumber: nil,
                cgDisplayMode: mode
            )

            if isCurrent {
                activeMode = item
            }
            if isGenuineHiDPI {
                hiDPIList.append(item)
            } else if pw == w && ph == h {
                loDPIList.append(item)
            }
        }

        let sorter: (DisplayResolutionMode, DisplayResolutionMode) -> Bool = { a, b in
            if a.width != b.width { return a.width > b.width }
            if a.height != b.height { return a.height > b.height }
            return a.refreshRate > b.refreshRate
        }

        hiDPIList.sort(by: sorter)
        loDPIList.sort(by: sorter)

        return (activeMode, hiDPIList, loDPIList)
    }

    /// Switches a display to the selected resolution mode immediately
    @discardableResult
    public func applyResolutionMode(_ mode: DisplayResolutionMode) -> Bool {
        if let cgMode = mode.cgDisplayMode {
            var config: CGDisplayConfigRef? = nil
            guard CGBeginDisplayConfiguration(&config) == .success, let cfg = config else {
                return false
            }
            let err = CGConfigureDisplayWithDisplayMode(cfg, mode.displayID, cgMode, nil)
            if err != .success {
                CGCancelDisplayConfiguration(cfg)
                return false
            }
            return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
        } else if let cgsMode = mode.cgsModeNumber {
            return MDP_SetDisplayModeNumber(mode.displayID, cgsMode)
        }
        return false
    }

    // MARK: - Custom HiDPI Override Plist Generator

    private func makeScaleResolutionData(width: UInt32, height: UInt32, hiDPIFlag: Bool) -> Data {
        var data = Data()
        var wBE = width.bigEndian
        var hBE = height.bigEndian
        withUnsafeBytes(of: &wBE) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &hBE) { data.append(contentsOf: $0) }
        if hiDPIFlag {
            var flag1: UInt32 = UInt32(1).bigEndian
            var flag2: UInt32 = UInt32(0x00200000).bigEndian
            withUnsafeBytes(of: &flag1) { data.append(contentsOf: $0) }
            withUnsafeBytes(of: &flag2) { data.append(contentsOf: $0) }
        }
        return data
    }

    public func generateOverridePlistXML(
        displayName: String,
        vendorID: UInt32,
        modelID: UInt32,
        resolutions: [(width: Int, height: Int)]
    ) -> String {
        var scaleDataEntries: [Data] = []

        for res in resolutions {
            let w = UInt32(max(640, res.width))
            let h = UInt32(max(480, res.height))
            scaleDataEntries.append(makeScaleResolutionData(width: w, height: h, hiDPIFlag: true))
            scaleDataEntries.append(makeScaleResolutionData(width: w * 2, height: h * 2, hiDPIFlag: false))
            scaleDataEntries.append(makeScaleResolutionData(width: w * 2, height: h * 2, hiDPIFlag: true))
        }

        let dict: [String: Any] = [
            "DisplayProductName": "\(displayName) (MacDisplayPro HiDPI)",
            "DisplayVendorID": Int(vendorID),
            "DisplayProductID": Int(modelID),
            "scale-resolutions": scaleDataEntries
        ]

        if let plistData = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
           let xmlString = String(data: plistData, encoding: .utf8) {
            return xmlString
        }
        return ""
    }

    public func systemOverrideFilePath(vendorID: UInt32, modelID: UInt32) -> String {
        let vendorDir = String(format: "DisplayVendorID-%x", vendorID)
        let productFile = String(format: "DisplayProductID-%x", modelID)
        return "/Library/Displays/Contents/Resources/Overrides/\(vendorDir)/\(productFile)"
    }

    public func installSystemHiDPIOverride(
        displayName: String,
        vendorID: UInt32,
        modelID: UInt32,
        resolutions: [(width: Int, height: Int)]
    ) -> (success: Bool, message: String) {
        let xml = generateOverridePlistXML(
            displayName: displayName,
            vendorID: vendorID,
            modelID: modelID,
            resolutions: resolutions
        )
        guard !xml.isEmpty else {
            return (false, "无法生成 HiDPI Override Plist 数据")
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("mdp_hidpi_override_\(vendorID)_\(modelID).plist")
        do {
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)
        } catch {
            return (false, "写入临时文件失败: \(error.localizedDescription)")
        }

        let vendorDir = String(format: "/Library/Displays/Contents/Resources/Overrides/DisplayVendorID-%x", vendorID)
        let destPath = systemOverrideFilePath(vendorID: vendorID, modelID: modelID)

        let shellCmd = "mkdir -p '\(vendorDir)' && cp '\(tempURL.path)' '\(destPath)' && chmod 644 '\(destPath)' && defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true"
        let appleScript = "do shell script \"\(shellCmd)\" with administrator privileges"

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", appleScript]

        let errPipe = Pipe()
        proc.standardError = errPipe

        do {
            try proc.run()
            proc.waitUntilExit()
            if proc.terminationStatus == 0 {
                return (true, "已成功注入系统 HiDPI 配置至 \(destPath)，重新插拔显示器或重启后生效；也可直接使用下方的「零重启虚拟 HiDPI 镜像」立即生效！")
            } else {
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? "未知错误"
                return (false, "安装未完成: \(errStr)")
            }
        } catch {
            return (false, "执行权限提升失败: \(error.localizedDescription)")
        }
    }
}
