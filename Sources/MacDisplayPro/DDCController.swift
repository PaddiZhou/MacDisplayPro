import Foundation
import AppKit
import CoreGraphics
import CDisplayBridge

public final class DDCController: @unchecked Sendable {
    public static let shared = DDCController()

    private let ddcQueue = DispatchQueue(label: "com.macdisplaypro.ddc.queue", qos: .userInitiated)
    private var pendingWorkItems: [String: DispatchWorkItem] = [:]
    private var lastSentValues: [String: UInt16] = [:]
    private var isDisplayAsleep: Bool = false
    private let lock = NSLock()

    private init() {
        let wsCenter = NSWorkspace.shared.notificationCenter
        wsCenter.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setSleepState(true)
        }
        wsCenter.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.setSleepState(false)
        }
    }

    private func setSleepState(_ asleep: Bool) {
        lock.lock()
        isDisplayAsleep = asleep
        if asleep {
            for (_, item) in pendingWorkItems {
                item.cancel()
            }
            pendingWorkItems.removeAll()
        }
        lock.unlock()
    }

    public var architectureName: String {
        switch MDP_GetDDCBackendType() {
        case .appleSiliconIOAVService:
            return "Apple Silicon (IOAVService I²C)"
        case .intelIOFramebuffer:
            return "Intel Mac (IOFramebuffer I²C)"
        default:
            return "Hybrid CoreDisplay"
        }
    }

    public func probeDisplay(_ displayID: CGDirectDisplayID) -> (supported: Bool, adapter: String) {
        var adapterNS: NSString? = nil
        let supported = MDP_ProbeDDCForDisplay(displayID, &adapterNS)
        let adapter = (adapterNS as String?) ?? "Unknown Adapter"
        return (supported, adapter)
    }

    private var lastHardwareWriteTime: CFAbsoluteTime = 0

    /// Reserves the DDC bus turnaround window without holding `lock` during sleep.
    /// Returns `false` if the display is asleep and I2C traffic should be skipped.
    private func waitForBusTurnaround(minGap: CFAbsoluteTime = 0.095) -> Bool {
        lock.lock()
        if isDisplayAsleep {
            lock.unlock()
            return false
        }
        let now = CFAbsoluteTimeGetCurrent()
        let targetTime = max(now, lastHardwareWriteTime + minGap)
        lastHardwareWriteTime = targetTime
        lock.unlock()

        let wait = targetTime - now
        if wait > 0 {
            Thread.sleep(forTimeInterval: wait)
        }
        return true
    }

    private func recordBusActivity() {
        lock.lock()
        lastHardwareWriteTime = max(lastHardwareWriteTime, CFAbsoluteTimeGetCurrent())
        lock.unlock()
    }

    /// Clears cached last-sent VCP values for a display (or a single VCP code) so subsequent writes go to hardware.
    public func invalidateCache(for displayID: CGDirectDisplayID, code: DDCCode? = nil) {
        lock.lock()
        if let code = code {
            lastSentValues.removeValue(forKey: "\(displayID)-\(code.rawValue)")
        } else {
            let prefix = "\(displayID)-"
            lastSentValues = lastSentValues.filter { !$0.key.hasPrefix(prefix) }
        }
        lock.unlock()
    }

    /// Writes a DDC VCP value asynchronously with EEPROM wear-leveling protection:
    /// - Skips redundant writes if the integer value hasn't changed (unless `force: true`)
    /// - Coalesces rapid slider movements with a configurable settle delay (default 160ms)
    /// - Enforces a minimum 95ms inter-command gap so multi-register bursts don't drop on monitor I2C scalers
    /// - Only caches values on verified I2C write success
    /// - Blocks I2C traffic when the screen is asleep
    public func writeDDCDebounced(
        displayID: CGDirectDisplayID,
        code: DDCCode,
        value: UInt16,
        force: Bool = false,
        delayMs: Int = 160,
        completion: (@Sendable (Bool) -> Void)? = nil
    ) {
        let key = "\(displayID)-\(code.rawValue)"
        lock.lock()
        if isDisplayAsleep {
            lock.unlock()
            return
        }
        if !force && lastSentValues[key] == value {
            lock.unlock()
            return
        }
        pendingWorkItems[key]?.cancel()

        let item = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            guard self.waitForBusTurnaround() else { return }

            var ok = MDP_WriteDDCValue(displayID, code.rawValue, value)
            if !ok {
                Thread.sleep(forTimeInterval: 0.08)
                ok = MDP_WriteDDCValue(displayID, code.rawValue, value)
            }

            self.lock.lock()
            self.lastHardwareWriteTime = max(self.lastHardwareWriteTime, CFAbsoluteTimeGetCurrent())
            if ok {
                self.lastSentValues[key] = value
            } else {
                self.lastSentValues.removeValue(forKey: key)
            }
            self.lock.unlock()

            if let completion = completion {
                DispatchQueue.main.async {
                    completion(ok)
                }
            }
        }
        pendingWorkItems[key] = item
        lock.unlock()

        ddcQueue.asyncAfter(deadline: .now() + .milliseconds(max(0, delayMs)), execute: item)
    }

    /// Reads a VCP value asynchronously from the monitor's I2C bus
    public func readDDC(
        displayID: CGDirectDisplayID,
        code: DDCCode,
        completion: @escaping @Sendable (MDP_DDCReadResult) -> Void
    ) {
        ddcQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.waitForBusTurnaround(minGap: 0.075) else {
                let empty = MDP_DDCReadResult(vcpCode: code.rawValue, currentValue: 0, maxValue: 0, success: false)
                DispatchQueue.main.async { completion(empty) }
                return
            }
            let res = MDP_ReadDDCValue(displayID, code.rawValue)
            self.recordBusActivity()
            DispatchQueue.main.async {
                completion(res)
            }
        }
    }

    /// Reads native macOS brightness (Built-in Liquid Retina / Apple Studio Display)
    public func getNativeBrightness(displayID: CGDirectDisplayID) -> Float? {
        var val: Float = 0.0
        if MDP_GetNativeDisplayBrightness(displayID, &val) {
            return val
        }
        return nil
    }

    /// Sets native macOS brightness
    @discardableResult
    public func setNativeBrightness(displayID: CGDirectDisplayID, brightness: Float) -> Bool {
        return MDP_SetNativeDisplayBrightness(displayID, brightness)
    }

    /// Applies hardware LUT Gamma adjustment
    public func applyGammaGain(
        displayID: CGDirectDisplayID,
        brightnessFactor: Float,
        warmth: Float = 0.0
    ) {
        let clampedB = max(0.08, min(1.0, brightnessFactor))
        let clampedW = max(0.0, min(1.0, warmth))

        let redMax   = CGGammaValue(clampedB)
        let greenMax = CGGammaValue(clampedB * (1.0 - clampedW * 0.15))
        let blueMax  = CGGammaValue(clampedB * (1.0 - clampedW * 0.35))

        CGSetDisplayTransferByFormula(
            displayID,
            0, redMax, 1.0,
            0, greenMax, 1.0,
            0, blueMax, 1.0
        )
    }

    public func resetGamma() {
        CGDisplayRestoreColorSyncSettings()
    }
}
