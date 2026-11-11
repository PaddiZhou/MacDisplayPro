import SwiftUI
import AppKit

// MARK: - Smart Workspace Scene Preset
public struct SmartScenePreset: Identifiable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let icon: String
    public let tint: Color
    public let targetWidth: Int
    public let brightness: Double
    public let contrast: Double
    public let xdrFactor: Double
    public let warmth: Double
    public let rgbGain: (Double, Double, Double)
    public let iccKeyword: String?

    public static let allScenes: [SmartScenePreset] = [
        SmartScenePreset(
            id: "favorite-daily",
            title: "点对点 4K 视网膜 (最爱默认)",
            subtitle: "1920×1080 HiDPI (底层 3840×2160 1:1 点对点) • 92% 亮度 • 16-bit FP16 • 绝对零毛边",
            icon: "star.circle.fill",
            tint: .indigo,
            targetWidth: 1920,
            brightness: 92,
            contrast: 72,
            xdrFactor: 1.0,
            warmth: 0.0,
            rgbGain: (100, 100, 100),
            iccKeyword: "Display P3"
        ),
        SmartScenePreset(
            id: "pro-design",
            title: "专业设计精准校色 (D65)",
            subtitle: "2048×1152 HiDPI • sRGB / P3 标准色域 • 6500K 硬件白点 • 零色偏",
            icon: "paintpalette.fill",
            tint: .pink,
            targetWidth: 2048,
            brightness: 75,
            contrast: 70,
            xdrFactor: 1.0,
            warmth: 0.0,
            rgbGain: (100, 100, 100),
            iccKeyword: "sRGB"
        ),
        SmartScenePreset(
            id: "hdr-cinema",
            title: "HDR 影院超亮观影",
            subtitle: "1920×1080 点对点 4K • 155% XDR 硬件高光增益 • DCI-P3 广色域",
            icon: "film.stack.fill",
            tint: .orange,
            targetWidth: 1920,
            brightness: 100,
            contrast: 80,
            xdrFactor: 1.55,
            warmth: 0.0,
            rgbGain: (100, 100, 100),
            iccKeyword: "DCI(P3)"
        ),
        SmartScenePreset(
            id: "night-coder",
            title: "深夜极客护眼编程",
            subtitle: "2048×1152 HiDPI • 42% 硬件低亮 + 35% 硬件暖色温 • 柔和低蓝光",
            icon: "moon.stars.fill",
            tint: .teal,
            targetWidth: 2048,
            brightness: 42,
            contrast: 65,
            xdrFactor: 0.85,
            warmth: 0.35,
            rgbGain: (100, 96, 88),
            iccKeyword: nil
        ),
        SmartScenePreset(
            id: "5k-multitask",
            title: "5K 超采样极限多任务",
            subtitle: "2560×1440 HiDPI (5120×2880 2x 超采) • 最大并排窗口视野",
            icon: "rectangle.split.3x1.fill",
            tint: .blue,
            targetWidth: 2560,
            brightness: 82,
            contrast: 72,
            xdrFactor: 1.0,
            warmth: 0.0,
            rgbGain: (100, 100, 100),
            iccKeyword: "Display P3"
        )
    ]
}

// MARK: - Reusable Glassmorphic Pro Card
public struct ProCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let icon: String
    let iconColor: Color
    let badgeText: String?
    let content: Content

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color = .accentColor,
        badgeText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.badgeText = badgeText
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconColor.opacity(0.16))
                        .frame(width: 30, height: 30)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5, weight: .bold))
                    if let sub = subtitle {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let badge = badgeText {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(iconColor.opacity(0.15)))
                        .foregroundColor(iconColor)
                }
            }

            Divider()
                .opacity(0.6)

            content
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Telemetry Metric Card
public struct MetricBadgeCard: View {
    let icon: String
    let tint: Color
    let label: String
    let value: String
    let detail: String

    public var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.22), lineWidth: 1)
        )
    }
}

// MARK: - Visual Resolution Scale Card (macOS System Settings Style)
public struct ResolutionScaleCard: View {
    let mode: DisplayResolutionMode
    let isFavoriteDefault: Bool
    let tagLabel: String?
    let onSelect: () -> Void
    var onToggleFavorite: (() -> Void)? = nil

    public init(
        mode: DisplayResolutionMode,
        isFavoriteDefault: Bool,
        tagLabel: String?,
        onSelect: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil
    ) {
        self.mode = mode
        self.isFavoriteDefault = isFavoriteDefault
        self.tagLabel = tagLabel
        self.onSelect = onSelect
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(mode.resolutionText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(mode.isCurrent ? .white : .primary)
                    Spacer()
                    if let onToggle = onToggleFavorite {
                        Button(action: onToggle) {
                            Image(systemName: isFavoriteDefault ? "star.fill" : "star")
                                .font(.system(size: 12))
                                .foregroundColor(isFavoriteDefault ? .yellow : (mode.isCurrent ? .white.opacity(0.7) : .secondary))
                        }
                        .buttonStyle(.plain)
                        .help(isFavoriteDefault ? "已设为常用默认分辨率 (点击取消)" : "设为常用默认分辨率")
                    } else if isFavoriteDefault {
                        Image(systemName: "star.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                    }
                    if mode.isCurrent {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.white)
                    }
                }

                Text("底层 \(mode.pixelWidth)×\(mode.pixelHeight) • \(mode.refreshRateText)")
                    .font(.system(size: 10.5))
                    .foregroundColor(mode.isCurrent ? .white.opacity(0.85) : .secondary)

                HStack(spacing: 4) {
                    if mode.isHiDPI {
                        Text("HiDPI 2x")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(mode.isCurrent ? Color.white.opacity(0.22) : Color.blue.opacity(0.15))
                            .foregroundColor(mode.isCurrent ? .white : .blue)
                            .cornerRadius(4)
                    }
                    if let tag = tagLabel {
                        Text(tag)
                            .font(.system(size: 9.5, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(mode.isCurrent ? Color.white.opacity(0.22) : Color.indigo.opacity(0.15))
                            .foregroundColor(mode.isCurrent ? .white : .indigo)
                            .cornerRadius(4)
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        mode.isCurrent
                        ? LinearGradient(colors: [Color.indigo, Color.blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color.secondary.opacity(0.08), Color.secondary.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(mode.isCurrent ? Color.indigo : Color.primary.opacity(0.08), lineWidth: mode.isCurrent ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Live GPU 256-Entry Hardware LUT Gamma Curve Visualizer
public struct GammaCurveVisualizer: View {
    let factor: Double
    let warmth: Double

    public var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.22))

                // Grid lines
                Path { path in
                    for i in 1...3 {
                        let x = w * CGFloat(i) / 4.0
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: h))
                        let y = h * CGFloat(i) / 4.0
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: w, y: y))
                    }
                }
                .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)

                // Diagonal 1:1 reference line
                Path { path in
                    path.move(to: CGPoint(x: 0, y: h))
                    path.addLine(to: CGPoint(x: w, y: 0))
                }
                .stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Active Hardware LUT Curve (Red/Luma channel)
                Path { path in
                    let steps = 64
                    let normBoost = max(0.0, min(1.4, factor - 1.0))
                    let gammaExp = factor >= 1.0 ? max(0.50, 1.0 - normBoost * 0.36) : 1.0
                    let scale = factor < 1.0 ? max(0.15, factor) : 1.0

                    for step in 0...steps {
                        let t = Double(step) / Double(steps)
                        let yVal = min(1.0, pow(t, gammaExp) * scale)
                        let px = CGFloat(t) * w
                        let py = h - CGFloat(yVal) * h
                        if step == 0 {
                            path.move(to: CGPoint(x: px, y: py))
                        } else {
                            path.addLine(to: CGPoint(x: px, y: py))
                        }
                    }
                }
                .stroke(
                    LinearGradient(colors: [.cyan, .orange], startPoint: .leading, endPoint: .trailing),
                    lineWidth: 2.5
                )

                // Blue channel curve when warm filter is active
                if warmth > 0.01 {
                    Path { path in
                        let steps = 64
                        let normBoost = max(0.0, min(1.4, factor - 1.0))
                        let gammaExp = factor >= 1.0 ? max(0.50, 1.0 - normBoost * 0.36) : 1.0
                        let scale = (factor < 1.0 ? max(0.15, factor) : 1.0) * (1.0 - warmth * 0.30)

                        for step in 0...steps {
                            let t = Double(step) / Double(steps)
                            let yVal = min(1.0, pow(t, gammaExp) * scale)
                            let px = CGFloat(t) * w
                            let py = h - CGFloat(yVal) * h
                            if step == 0 {
                                path.move(to: CGPoint(x: px, y: py))
                            } else {
                                path.addLine(to: CGPoint(x: px, y: py))
                            }
                        }
                    }
                    .stroke(Color.blue.opacity(0.7), lineWidth: 1.5)
                }
            }
        }
    }
}
