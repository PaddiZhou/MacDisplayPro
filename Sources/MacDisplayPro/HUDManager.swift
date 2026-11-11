import AppKit
import SwiftUI

/// Displays a sleek, translucent floating OSD HUD pill at the bottom of the active display
/// whenever brightness, volume, XDR boost, resolution, or color profile changes.
@MainActor
public final class HUDManager: ObservableObject {
    public static let shared = HUDManager()

    @Published public var iconName: String = "sun.max.fill"
    @Published public var title: String = "亮度"
    @Published public var subtitle: String = "80%"
    @Published public var progress: Double? = 0.8
    @Published public var accentColor: Color = .blue

    private var hudWindow: NSWindow?
    private var hideWorkItem: DispatchWorkItem?

    private init() {}

    public func show(
        icon: String,
        title: String,
        subtitle: String,
        progress: Double? = nil,
        tint: Color = .blue
    ) {
        self.iconName = icon
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.accentColor = tint

        let win = ensureHUDWindow()
        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let w: CGFloat = 280
            let h: CGFloat = progress != nil ? 76 : 60
            let x = screen.frame.midX - w / 2
            let y = screen.frame.minY + 96
            win.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
        }

        win.alphaValue = 1.0
        win.orderFrontRegardless()

        hideWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let win = self?.hudWindow else { return }
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.25
                    win.animator().alphaValue = 0.0
                }, completionHandler: {
                    win.orderOut(nil)
                })
            }
        }
        hideWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4, execute: item)
    }

    private func ensureHUDWindow() -> NSWindow {
        if let existing = hudWindow {
            return existing
        }
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 76),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.isReleasedWhenClosed = false
        win.level = .statusBar
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        win.contentView = NSHostingView(rootView: HUDToastView(hud: self))
        self.hudWindow = win
        return win
    }
}

@MainActor
struct HUDToastView: View {
    @ObservedObject var hud: HUDManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: hud.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(hud.accentColor)
                    .frame(width: 24)

                Text(hud.title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Text(hud.subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            if let prog = hud.progress {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 6)
                        Capsule()
                            .fill(hud.accentColor)
                            .frame(width: max(6, min(geo.size.width, geo.size.width * CGFloat(prog))), height: 6)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThickMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}
