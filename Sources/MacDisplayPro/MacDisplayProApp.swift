import SwiftUI
import AppKit
import CoreGraphics
import CDisplayBridge

@main
@MainActor
public struct MacDisplayProMain {
    public static func main() {
        let args = CommandLine.arguments
        if args.count > 1 && args.contains(where: { $0.hasPrefix("--") && !$0.hasPrefix("-NS") }) {
            runCLIMode(args: Array(args.dropFirst()))
            return
        }

        let app = NSApplication.shared
        let delegate = MacDisplayProAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    // Built-in CLI Interface (like betterdisplaycli)
    @MainActor
    private static func runCLIMode(args: [String]) {
        let store = DisplayStore.shared
        switch args.first {
        case "--list":
            print("=== MacDisplayPro Connected Displays (\(DDCController.shared.architectureName)) ===")
            for d in store.displays {
                let res = d.currentMode?.resolutionText ?? "Unknown"
                let rate = d.currentMode?.refreshRateText ?? ""
                let hidpi = (d.currentMode?.isHiDPI ?? false) ? "HiDPI 2x" : "LoDPI 1x"
                print("• [ID \(d.id)] \(d.name) | Vendor: \(d.vendorHex) Model: \(d.modelHex) | \(res) @ \(rate) (\(hidpi)) | DDC: \(d.supportsDDC) | MaxEDR: \(String(format: "%.2fx", d.maxPotentialEDR))")
                if let prof = store.smartProfiles[d.id] {
                    print("  └─ 智能诊断: \(prof.summaryReport)")
                }
            }
        case "--auto-adapt":
            store.performAutoAdaptAllDisplays(silent: false)
            print("✅ \(store.statusMessage)")
            for d in store.displays {
                if let prof = store.smartProfiles[d.id] {
                    print("• [\(d.name)] \(prof.summaryReport)")
                }
            }
        case "--fix-icons":
            if let disp = store.selectedDisplay {
                let res = IconAntiAliasingOptimizer.shared.performOneClickAntiAliasingFix(for: disp)
                print("✅ \(res)")
            }
        case "--lock-default":
            if let disp = store.selectedDisplay {
                // Ensure 1920x1080 HiDPI (3840x2160 1:1 pixel-perfect 4K Retina) is active and locked as permanent default
                if let favMode = disp.hiDPIModes.first(where: { $0.width == 1920 && $0.height == 1080 }) {
                    _ = HiDPIManager.shared.applyResolutionMode(favMode)
                }
                // Force Pure RGB 4:4:4 Full Range (0-255) over the existing HDMI cable (eliminating YCbCr chroma subsampling jagged edges)
                _ = MDP_ForceRGB444FullRangeLink(disp.id)
                // Set default hardware brightness to 92%
                _ = MDP_WriteDDCValue(disp.id, DDCCode.brightness.rawValue, 92)
                store.ddcBrightness[disp.id] = 92.0
                _ = IconAntiAliasingOptimizer.shared.repairLegacyAppIconsSegmentation()
                IconAntiAliasingOptimizer.shared.rebuildRetinaIconAndDockCache()
                store.refreshDisplays()
                if let updated = store.selectedDisplay {
                    let msg = AutoAdaptEngine.shared.lockCurrentDisplayStateAsDefault(updated)
                    print(msg)
                    print("☀️ 已将显示器硬件亮度锁定并下发为: 92%")
                    print("🎨 已免换线强制开启 HDMI RGB 4:4:4 全色度 + Full Range (0-255)")
                }
                if let tele = ColorAndHardwareEngine.shared.telemetry[disp.id] {
                    print("• 硬件深度遥测: \(tele.framebufferDepthDescription) | EDID MaxBpc=\(tele.maxBpc)-bit | 峰值像素时钟=\(tele.maxPixelRateMHz)MHz")
                }
            }
        case "--ddc-brightness":
            guard args.count >= 2, let val = UInt16(args[1]), let disp = store.displays.first(where: { !$0.isBuiltin }) ?? store.displays.first else {
                print("Usage: MacDisplayPro --ddc-brightness <0-100>")
                return
            }
            let ok = MDP_WriteDDCValue(disp.id, DDCCode.brightness.rawValue, val)
            print("DDC Brightness (0x10) -> \(val)% on \(disp.name): \(ok ? "SUCCESS" : "FALLBACK")")
        case "--help":
            print("""
            MacDisplayPro CLI Usage:
              MacDisplayPro --list                     List all displays, HiDPI modes, DDC & EDR capabilities
              MacDisplayPro --ddc-brightness <0-100>   Set hardware DDC brightness on primary external monitor
            """)
        default:
            print("Unknown argument. Use --help or launch without arguments for GUI.")
        }
    }
}

@MainActor
public final class MacDisplayProAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var studioWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusBarItem()
        openStudioWindow()
    }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openStudioWindow()
        }
        return true
    }

    public func applicationWillTerminate(_ notification: Notification) {
        XDRBrightnessEngine.shared.disableAllOverlays()
        VirtualDisplayManager.shared.removeAllVirtualDisplays()
    }

    private func setupStatusBarItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "display.2", accessibilityDescription: "MacDisplayPro")
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        self.statusItem = item

        popover.contentSize = NSSize(width: 350, height: 480)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(onOpenStudio: { [weak self] in
                self?.popover.performClose(nil)
                self?.openStudioWindow()
            })
        )
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            DisplayStore.shared.refreshDisplays()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    public func openStudioWindow() {
        if let existing = studioWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "MacDisplayPro — 自定义 HiDPI • XDR 1600nits • 虚拟显示器 • DDC/CI 硬件中枢"
        win.center()
        win.isReleasedWhenClosed = false
        win.contentView = NSHostingView(rootView: StudioMainView())
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.studioWindow = win
    }
}
