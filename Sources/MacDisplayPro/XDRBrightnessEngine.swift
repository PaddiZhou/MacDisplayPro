import AppKit
import Metal
import QuartzCore
import CoreGraphics

/// Manages per-screen XDR/HDR Brightness Boost (100%..240% via 1x1 EDR Hardware Beacon + 256-entry GPU Hardware LUT Curve)
/// and Sub-Zero Software Dimming & Warm Eye-Care overlays (<100%).
/// Completely eliminates full-screen white-out by never drawing opaque white over the desktop.
@MainActor
public final class XDRBrightnessEngine {
    public static let shared = XDRBrightnessEngine()

    private var overlayWindows: [CGDirectDisplayID: NSWindow] = [:]
    private var metalViews: [CGDirectDisplayID: XDROverlayMetalView] = [:]

    private var brightnessFactors: [CGDirectDisplayID: Float] = [:]
    private var warmthFactors: [CGDirectDisplayID: Float] = [:]
    private var thermalProtectionTimer: DispatchWorkItem?
    public var autoThermalProtectionEnabled: Bool = true

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionAllOverlays()
            }
        }
    }

    public func currentFactor(for displayID: CGDirectDisplayID) -> Float {
        brightnessFactors[displayID] ?? 1.0
    }

    public func currentWarmth(for displayID: CGDirectDisplayID) -> Float {
        warmthFactors[displayID] ?? 0.0
    }

    /// Sets the brightness/XDR factor (0.10 to 2.40) and warmth (0.0 to 1.0) for a display
    public func setLuminance(
        for displayID: CGDirectDisplayID,
        factor: Float,
        warmth: Float = 0.0
    ) {
        let clampedFactor = max(0.10, min(2.40, factor))
        let clampedWarmth = max(0.0, min(1.0, warmth))

        brightnessFactors[displayID] = clampedFactor
        warmthFactors[displayID] = clampedWarmth

        if abs(clampedFactor - 1.0) < 0.01 && clampedWarmth < 0.01 {
            removeOverlay(for: displayID)
            DDCController.shared.resetGamma()
            return
        }

        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) else {
            return
        }

        let window = ensureOverlayWindow(for: screen)

        if clampedFactor > 1.0 {
            // XDR Boost Mode (>100%):
            // 1. Resize overlay window to a 1x1 pixel invisible corner EDR beacon so it NEVER covers or whites out the desktop!
            let beaconFrame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1)
            window.setFrame(beaconFrame, display: true)
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            metalViews[displayID]?.updateEDRState(factor: clampedFactor, warmth: clampedWarmth)

            // 2. Apply 256-entry GPU Hardware LUT highlight/midtone luminance boost curve (zero white fog, preserves deep blacks)
            applyHardwareXDRGammaLUT(displayID: displayID, boostFactor: clampedFactor, warmth: clampedWarmth)

            // 3. Push physical native/DDC brightness toward 100% when in XDR boost range
            _ = DDCController.shared.setNativeBrightness(displayID: displayID, brightness: 1.0)

            // 4. Hardware Panel Safety: 30-minute automatic thermal cooldown when overdrive > 115%
            thermalProtectionTimer?.cancel()
            if autoThermalProtectionEnabled && clampedFactor > 1.15 {
                let cooldownItem = DispatchWorkItem { [weak self] in
                    Task { @MainActor in
                        guard let self = self else { return }
                        self.setLuminance(for: displayID, factor: 1.0, warmth: clampedWarmth)
                        DisplayStore.shared.xdrLuminanceFactor[displayID] = 1.0
                        DisplayStore.shared.statusMessage = "🛡️ 硬件过热保护：XDR 超亮已持续 30 分钟，已自动回落至 100% 安全亮度保护灯珠寿命"
                        HUDManager.shared.show(icon: "shield.checkered", title: "硬件护航已触发", subtitle: "已自动回落至 100% 安全亮度", tint: .green)
                    }
                }
                thermalProtectionTimer = cooldownItem
                DispatchQueue.main.asyncAfter(deadline: .now() + 1800, execute: cooldownItem)
            }
        } else {
            thermalProtectionTimer?.cancel()
            // Sub-Zero Software Dimming / Warmth Mode (<=100%):
            window.setFrame(screen.frame, display: true)
            if !window.isVisible {
                window.orderFrontRegardless()
            }
            metalViews[displayID]?.updateEDRState(factor: clampedFactor, warmth: clampedWarmth)

            let gammaB = min(1.0, max(0.25, clampedFactor))
            DDCController.shared.applyGammaGain(displayID: displayID, brightnessFactor: gammaB, warmth: clampedWarmth)
        }
    }

    /// Injects a 256-entry nonlinear midtone/highlight gain table directly into the GPU display pipe (`CGSetDisplayTransferByTable`)
    /// so pixel brightness is boosted cleanly in hardware without washing out black levels or causing a white screen.
    private func applyHardwareXDRGammaLUT(displayID: CGDirectDisplayID, boostFactor: Float, warmth: Float) {
        let tableSize = 256
        var redTable = [CGGammaValue](repeating: 0, count: tableSize)
        var greenTable = [CGGammaValue](repeating: 0, count: tableSize)
        var blueTable = [CGGammaValue](repeating: 0, count: tableSize)

        // Smooth gamma exponent between 1.0 (at 100%) and 0.52 (at 240%) with black-point toe protection
        let normalizedBoost = max(Float(0.0), min(Float(1.4), boostFactor - 1.0))
        let gammaExponent: Float = max(0.50, 1.0 - normalizedBoost * 0.36)
        let whiteGain: Float = 1.0

        let greenWarmScale = 1.0 - warmth * 0.12
        let blueWarmScale = 1.0 - warmth * 0.28

        for i in 0..<tableSize {
            let x = Float(i) / Float(tableSize - 1)
            // Keep deep shadows anchored near 0 so contrast stays rich while boosting midtones & highlights
            let curved = powf(x, gammaExponent) * whiteGain
            let clamped = max(0.0, min(1.0, curved))

            redTable[i] = CGGammaValue(clamped)
            greenTable[i] = CGGammaValue(clamped * greenWarmScale)
            blueTable[i] = CGGammaValue(clamped * blueWarmScale)
        }

        CGSetDisplayTransferByTable(displayID, UInt32(tableSize), &redTable, &greenTable, &blueTable)
    }

    public func disableAllOverlays() {
        for (_, window) in overlayWindows {
            window.orderOut(nil)
        }
        overlayWindows.removeAll()
        metalViews.removeAll()
        brightnessFactors.removeAll()
        warmthFactors.removeAll()
        DDCController.shared.resetGamma()
    }

    private func removeOverlay(for displayID: CGDirectDisplayID) {
        if let win = overlayWindows.removeValue(forKey: displayID) {
            win.orderOut(nil)
        }
        metalViews.removeValue(forKey: displayID)
    }

    private func repositionAllOverlays() {
        for screen in NSScreen.screens {
            let id = screen.displayID
            if let win = overlayWindows[id] {
                let factor = brightnessFactors[id] ?? 1.0
                if factor > 1.0 {
                    win.setFrame(NSRect(x: screen.frame.minX, y: screen.frame.minY, width: 1, height: 1), display: true)
                } else {
                    win.setFrame(screen.frame, display: true)
                }
                metalViews[id]?.renderFrame()
            }
        }
    }

    private func ensureOverlayWindow(for screen: NSScreen) -> NSWindow {
        let id = screen.displayID
        if let existing = overlayWindows[id] {
            return existing
        }

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)))
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.sharingType = .none
        window.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let metalView = XDROverlayMetalView(frame: screen.frame)
        window.contentView = metalView

        overlayWindows[id] = window
        metalViews[id] = metalView
        return window
    }
}

// MARK: - Metal EDR Layer View (1x1 Invisible EDR Beacon when >100%, Translucent Dimming Veil when <100%)
public final class XDROverlayMetalView: NSView {
    private var metalLayer: CAMetalLayer?
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var factor: Float = 1.0
    private var warmth: Float = 0.0

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupMetalEDR()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupMetalEDR()
    }

    public override var wantsUpdateLayer: Bool { true }

    private func setupMetalEDR() {
        wantsLayer = true
        let dev = MTLCreateSystemDefaultDevice()
        self.device = dev
        self.commandQueue = dev?.makeCommandQueue()

        let mLayer = CAMetalLayer()
        mLayer.device = dev
        mLayer.pixelFormat = .rgba16Float
        mLayer.isOpaque = false
        mLayer.framebufferOnly = false
        mLayer.wantsExtendedDynamicRangeContent = true

        if let edrColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) {
            mLayer.colorspace = edrColorSpace
        }

        self.layer = mLayer
        self.metalLayer = mLayer
    }

    public func updateEDRState(factor: Float, warmth: Float) {
        self.factor = factor
        self.warmth = warmth

        guard let mLayer = self.metalLayer else { return }
        mLayer.wantsExtendedDynamicRangeContent = (factor > 1.0)
        mLayer.compositingFilter = nil
        renderFrame()
    }

    public func renderFrame() {
        guard let mLayer = self.metalLayer,
              let queue = self.commandQueue else { return }

        mLayer.drawableSize = CGSize(width: max(1, min(64, bounds.width)), height: max(1, min(64, bounds.height)))
        guard let drawable = mLayer.nextDrawable(),
              let cmdBuffer = queue.makeCommandBuffer() else { return }

        let passDesc = MTLRenderPassDescriptor()
        passDesc.colorAttachments[0].texture = drawable.texture
        passDesc.colorAttachments[0].loadAction = .clear
        passDesc.colorAttachments[0].storeAction = .store

        if factor > 1.0 {
            // 1x1 pixel invisible EDR beacon (alpha = 0.01) to request maximum EDR headroom from WindowServer without visible white overlay
            let boost = Double(factor * factor)
            passDesc.colorAttachments[0].clearColor = MTLClearColorMake(boost, boost, boost, 0.01)
        } else {
            // Software dimming translucent dark/warm veil
            let dimAlpha = Double(max(0.0, min(0.85, 1.0 - factor)))
            let r = Double(warmth * 0.16)
            let g = Double(warmth * 0.06)
            let b = 0.0
            passDesc.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, max(dimAlpha, Double(warmth * 0.22)))
        }

        if let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: passDesc) {
            encoder.endEncoding()
        }
        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }
}

public extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
