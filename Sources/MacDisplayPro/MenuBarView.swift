import SwiftUI
import AppKit

@MainActor
public struct MenuBarPopoverView: View {
    @ObservedObject var store: DisplayStore
    @ObservedObject var virtualManager: VirtualDisplayManager
    @ObservedObject var colorEngine: ColorAndHardwareEngine = .shared
    var onOpenStudio: () -> Void

    public init(
        store: DisplayStore,
        virtualManager: VirtualDisplayManager,
        onOpenStudio: @escaping () -> Void
    ) {
        self.store = store
        self.virtualManager = virtualManager
        self.onOpenStudio = onOpenStudio
    }

    public init(onOpenStudio: @escaping () -> Void) {
        self.store = .shared
        self.virtualManager = .shared
        self.onOpenStudio = onOpenStudio
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            // 1. Top Brand Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .blue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 26, height: 26)
                    Image(systemName: "display.2")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Text("MacDisplayPro")
                        .font(.system(size: 13.5, weight: .bold))
                    Text("HiDPI • XDR • ColorSync • DDC")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: { store.refreshDisplays() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("刷新显示器状态")

                Button("主控制台") {
                    onOpenStudio()
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .controlSize(.small)
            }

            if let disp = store.selectedDisplay {
                // 2. Active Display Card
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Text(disp.name)
                                    .font(.system(size: 13, weight: .bold))
                                Text((colorEngine.selectedBitDepth[disp.id] ?? .bit16).title)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(Color.orange.opacity(0.18))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                                if disp.supportsDDC {
                                    Text("DDC")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1.5)
                                        .background(Color.green.opacity(0.18))
                                        .foregroundColor(.green)
                                        .cornerRadius(4)
                                }
                            }
                            if let cur = disp.currentMode {
                                Text("\(cur.resolutionText) (\(cur.pixelWidth)×\(cur.pixelHeight) 2x) @ \(cur.refreshRateText)")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()

                        Button(action: { store.lockCurrentAsDefault(for: disp.id) }) {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.bordered)
                        .tint(.green)
                        .controlSize(.small)
                        .help("锁定当前状态为永久默认配置")

                        Button(action: { store.performSmartAutoAdapt(for: disp.id) }) {
                            Label("智能适配", systemImage: "wand.and.stars")
                                .font(.system(size: 10.5, weight: .bold))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.small)
                    }

                    // Quick Smart Scene Pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(SmartScenePreset.allScenes) { scene in
                                Button(action: {
                                    store.applySmartScene(scene, for: disp.id)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: scene.icon)
                                            .font(.system(size: 10))
                                            .foregroundColor(scene.tint)
                                        Text(scene.title.components(separatedBy: " ").first ?? scene.title)
                                            .font(.system(size: 10.5, weight: .medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(scene.tint.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

                // 3. Sliders Card (Brightness, XDR Boost, Volume)
                VStack(alignment: .leading, spacing: 9) {
                    // Hardware Brightness
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: "sun.max.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 11))
                            Text("物理硬件亮度 (DDC 0x10)")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            Text("\(Int(store.ddcBrightness[disp.id] ?? 80))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { store.ddcBrightness[disp.id] ?? 80 },
                                set: { store.setHardwareBrightness(for: disp.id, value: $0) }
                            ),
                            in: 0...100
                        )
                    }

                    // XDR / LUT Boost & Sub-Zero Dimming
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.orange)
                                .font(.system(size: 11))
                            Text("XDR 硬件 LUT 增益 / 暗光")
                                .font(.system(size: 11, weight: .semibold))
                            Spacer()
                            let factor = store.xdrLuminanceFactor[disp.id] ?? 1.0
                            Text("\(Int(factor * 100))%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(factor > 1.02 ? .orange : .secondary)
                        }
                        Slider(
                            value: Binding(
                                get: { store.xdrLuminanceFactor[disp.id] ?? 1.0 },
                                set: { store.setXDRLuminance(for: disp.id, factor: $0) }
                            ),
                            in: 0.20...2.20
                        )
                    }

                    // Monitor Volume
                    if !disp.isBuiltin {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Image(systemName: (store.ddcMuted[disp.id] ?? false) ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(.blue)
                                    .font(.system(size: 11))
                                Text("显示器扬声器 (DDC 0x62)")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Button((store.ddcMuted[disp.id] ?? false) ? "取消静音" : "静音") {
                                    store.toggleHardwareMute(for: disp.id)
                                }
                                .controlSize(.mini)
                                .buttonStyle(.bordered)
                                Text("\(Int(store.ddcVolume[disp.id] ?? 50))%")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: Binding(
                                    get: { store.ddcVolume[disp.id] ?? 50 },
                                    set: { store.setHardwareVolume(for: disp.id, value: $0) }
                                ),
                                in: 0...100
                            )
                        }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))

                // 4. Quick HiDPI Scale Grid
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("HiDPI 2x 视网膜缩放档位")
                            .font(.system(size: 11, weight: .bold))
                        Spacer()
                        Button("修复图标锯齿") {
                            store.statusMessage = IconAntiAliasingOptimizer.shared.performOneClickAntiAliasingFix(for: disp)
                        }
                        .controlSize(.mini)
                        .buttonStyle(.bordered)
                        .tint(.teal)
                    }

                    let quickModes = disp.hiDPIModes.isEmpty ? Array(disp.loDPIModes.prefix(4)) : Array(disp.hiDPIModes.prefix(4))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                        ForEach(quickModes) { mode in
                            let isFav = store.isFavoriteMode(mode, for: disp)
                            Button(action: { store.switchResolution(mode) }) {
                                HStack(spacing: 4) {
                                    if isFav {
                                        Image(systemName: "star.fill")
                                            .font(.system(size: 9))
                                            .foregroundColor(.yellow)
                                    }
                                    Text(mode.resolutionText)
                                        .font(.system(size: 11, weight: mode.isCurrent ? .bold : .medium, design: .monospaced))
                                    Spacer()
                                    Text("2x")
                                        .font(.system(size: 9, weight: .bold))
                                        .opacity(0.8)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(mode.isCurrent ? Color.indigo : Color.secondary.opacity(0.12))
                                )
                                .foregroundColor(mode.isCurrent ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // 5. Quick Bit-Depth & ColorSync ICC Switcher Bar
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("屏幕色深:")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(BitDepthChoice.allCases) { choice in
                            let isSelected = (colorEngine.selectedBitDepth[disp.id] ?? .bit16) == choice
                            Button(action: {
                                store.statusMessage = colorEngine.selectBitDepth(choice, for: disp.id)
                                HUDManager.shared.show(icon: "cpu.fill", title: "屏幕色深已切换", subtitle: choice.title, tint: .orange)
                            }) {
                                Text(choice.title)
                                    .font(.system(size: 10.5, weight: isSelected ? .bold : .medium, design: .monospaced))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(RoundedRectangle(cornerRadius: 5).fill(isSelected ? Color.orange : Color.secondary.opacity(0.12)))
                                    .foregroundColor(isSelected ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Text("色彩配置:")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundColor(.secondary)
                        ForEach(colorEngine.availableProfiles.prefix(3)) { prof in
                            Button(prof.name.contains("Display P3") ? "Display P3" : (prof.name.contains("sRGB") ? "sRGB" : "原生 ICC")) {
                                let res = colorEngine.applyColorProfile(prof, for: disp.id)
                                store.statusMessage = res.message
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                        }
                        Spacer()
                    }
                }

                Divider()

                // Footer
                HStack {
                    Text(store.statusMessage)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("退出") {
                        XDRBrightnessEngine.shared.disableAllOverlays()
                        NSApplication.shared.terminate(nil)
                    }
                    .controlSize(.mini)
                }
            }
        }
        .padding(13)
        .frame(width: 365)
    }
}
