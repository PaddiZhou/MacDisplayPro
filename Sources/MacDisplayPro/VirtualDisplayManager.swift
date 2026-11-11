import Foundation
import AppKit
import CoreGraphics
import CDisplayBridge

public struct ActiveVirtualDisplay: Identifiable {
    public let id: UUID
    public let handle: MDPVirtualDisplayHandle
    public let name: String
    public let baseWidth: UInt32
    public let baseHeight: UInt32
    public let refreshRate: Double
    public let isHiDPI: Bool
    public var mirroredPhysicalDisplayID: CGDirectDisplayID?

    public var displayID: CGDirectDisplayID {
        handle.displayID
    }
}

@MainActor
public final class VirtualDisplayManager: ObservableObject {
    public static let shared = VirtualDisplayManager()

    @Published public private(set) var activeVirtualDisplays: [ActiveVirtualDisplay] = []
    private var pipWindows: [CGDirectDisplayID: VirtualDisplayPiPWindowController] = [:]
    private var serialCounter: UInt32 = 1001

    private init() {}

    public var isSupportedByRuntime: Bool {
        MDPVirtualDisplayHandle.isSupported()
    }

    /// Creates a new custom CGVirtualDisplay with full multi-scale HiDPI mode list
    @discardableResult
    public func createVirtualDisplay(
        name: String,
        width: UInt32,
        height: UInt32,
        refreshRate: Double = 60.0,
        hiDPI: Bool = true
    ) -> ActiveVirtualDisplay? {
        let ratio = Double(width) / Double(max(1, height))

        // Generate a rich set of scaled resolutions sharing the same aspect ratio so macOS System Settings & MacDisplayPro show multiple HiDPI choices
        let candidateWidths: [UInt32] = [
            width,
            UInt32((Double(width) * 0.90).rounded()),
            UInt32((Double(width) * 0.80).rounded()),
            UInt32((Double(width) * 0.75).rounded()),
            UInt32((Double(width) * 0.67).rounded()),
            1920,
            1600,
            1440,
            1280
        ]

        var specs: [MDPVirtualDisplayModeSpec] = []
        var seenWidths = Set<UInt32>()

        for w in candidateWidths {
            let evenW = (w / 2) * 2
            guard evenW >= 1024, !seenWidths.contains(evenW) else { continue }
            seenWidths.insert(evenW)
            let evenH = (UInt32((Double(evenW) / ratio).rounded()) / 2) * 2
            specs.append(MDPVirtualDisplayModeSpec(width: evenW, height: evenH, refreshRate: refreshRate))
        }

        let maxW = hiDPI ? min(7680, width * 2) : width
        let maxH = hiDPI ? min(4320, height * 2) : height
        let currentSerial = serialCounter
        serialCounter += 1

        guard let handle = MDPVirtualDisplayHandle.create(
            withName: name,
            vendorID: 0xF0F0,
            productID: UInt32(0x2000 + currentSerial),
            serialNum: currentSerial,
            sizeInMillimeters: CGSize(width: 600, height: 340),
            maxPixelsWide: maxW,
            maxPixelsHigh: maxH,
            hiDPI: hiDPI,
            modes: specs
        ) else {
            return nil
        }

        let item = ActiveVirtualDisplay(
            id: UUID(),
            handle: handle,
            name: name,
            baseWidth: width,
            baseHeight: height,
            refreshRate: refreshRate,
            isHiDPI: hiDPI,
            mirroredPhysicalDisplayID: nil
        )
        activeVirtualDisplays.append(item)
        return item
    }

    /// Zero-Reboot HiDPI Dummy Mirroring:
    /// Creates a 2x HiDPI Virtual Display and mirrors the target physical display to it, unlocking arbitrary HiDPI scaling immediately without rebooting.
    public func enableZeroRebootHiDPIMirror(
        forPhysicalDisplay physicalID: CGDirectDisplayID,
        physicalName: String,
        targetScaledWidth: UInt32,
        targetScaledHeight: UInt32,
        refreshRate: Double = 60.0
    ) -> Bool {
        guard let virtualDisp = createVirtualDisplay(
            name: "\(physicalName) HiDPI Engine",
            width: targetScaledWidth,
            height: targetScaledHeight,
            refreshRate: refreshRate,
            hiDPI: true
        ) else {
            return false
        }

        let vID = virtualDisp.displayID
        guard vID != kCGNullDirectDisplay else { return false }

        // Mirror physical display to the high-DPI virtual display master
        let ok = MDP_ConfigureHardwareMirror(vID, physicalID, true)
        if ok, let idx = activeVirtualDisplays.firstIndex(where: { $0.id == virtualDisp.id }) {
            activeVirtualDisplays[idx].mirroredPhysicalDisplayID = physicalID
        }
        return ok
    }

    public func removeVirtualDisplay(id: UUID) {
        guard let idx = activeVirtualDisplays.firstIndex(where: { $0.id == id }) else { return }
        let item = activeVirtualDisplays[idx]
        if let mirroredPhys = item.mirroredPhysicalDisplayID {
            _ = MDP_ConfigureHardwareMirror(kCGNullDirectDisplay, mirroredPhys, false)
        }
        closePiPWindow(for: item.displayID)
        item.handle.invalidate()
        activeVirtualDisplays.remove(at: idx)
    }

    public func removeAllVirtualDisplays() {
        for item in activeVirtualDisplays {
            if let mirroredPhys = item.mirroredPhysicalDisplayID {
                _ = MDP_ConfigureHardwareMirror(kCGNullDirectDisplay, mirroredPhys, false)
            }
            closePiPWindow(for: item.displayID)
            item.handle.invalidate()
        }
        activeVirtualDisplays.removeAll()
    }

    // MARK: - Picture-in-Picture (PiP) Virtual Screen Viewer
    public func openPiPWindow(for virtualDisplay: ActiveVirtualDisplay) {
        let dispID = virtualDisplay.displayID
        if let existing = pipWindows[dispID] {
            existing.showWindow(nil)
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = VirtualDisplayPiPWindowController(displayID: dispID, title: "画中画预览: \(virtualDisplay.name)")
        pipWindows[dispID] = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closePiPWindow(for displayID: CGDirectDisplayID) {
        if let ctrl = pipWindows.removeValue(forKey: displayID) {
            ctrl.stopTimer()
            ctrl.close()
        }
    }
}

// MARK: - Live PiP Preview Window Controller
@MainActor
public final class VirtualDisplayPiPWindowController: NSWindowController {
    private let displayID: CGDirectDisplayID
    private let imageView = NSImageView()
    private var timer: Timer?

    public init(displayID: CGDirectDisplayID, title: String) {
        self.displayID = displayID
        let win = NSWindow(
            contentRect: NSRect(x: 160, y: 160, width: 640, height: 360),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = title
        win.level = .floating
        win.backgroundColor = .black
        win.isReleasedWhenClosed = false

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = win.contentView?.bounds ?? .zero
        imageView.autoresizingMask = [.width, .height]
        win.contentView?.addSubview(imageView)

        super.init(window: win)
        startCaptureLoop()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func startCaptureLoop() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.captureFrame()
            }
        }
    }

    public func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func captureFrame() {
        guard let window = self.window, window.isVisible else { return }
        if let cgImg = CGDisplayCreateImage(displayID) {
            let size = NSSize(width: cgImg.width, height: cgImg.height)
            imageView.image = NSImage(cgImage: cgImg, size: size)
        }
    }
}
