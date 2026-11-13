import SwiftUI
import AppKit
import CoreGraphics
import CDisplayBridge

@MainActor
public struct StudioMainView: View {
    @ObservedObject var store: DisplayStore = .shared
    @ObservedObject var virtualManager: VirtualDisplayManager = .shared
    @ObservedObject var iconOptimizer: IconAntiAliasingOptimizer = .shared
    @ObservedObject var colorEngine: ColorAndHardwareEngine = .shared

    private let navItems: [(tag: Int, title: String, subtitle: String, icon: String, tint: Color)] = [
        (0, "智能概览与情景预设", "一键工作模式 • 黄金缩放卡片", "sparkles.rectangle.stack.fill", .indigo),
        (1, "HiDPI 与分辨率引擎", "2x 视网膜缩放 • 零重启虚拟镜像", "viewfinder.rectangular", .blue),
        (2, "XDR 提亮与伽马曲线", "256 级硬件 LUT • 护眼暗光滤镜", "sun.max.trianglebadge.exclamationmark", .orange),
        (3, "色彩配置与 12-bit 极限", "ColorSync ICC • 16-bit FP16 • RGB 增益", "paintpalette.fill", .pink),
        (4, "图标与字体抗锯齿", "Dock @2x 重建 • VCP 0x87 锐度校准", "sparkles.tv", .teal),
        (5, "虚拟显示器与 DDC 总线", "CGVirtualDisplay • 画中画 • I²C 调试", "cpu.fill", .purple)
    ]

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarView
                .frame(minWidth: 245, idealWidth: 260, maxWidth: 280)
        } detail: {
            if let disp = store.selectedDisplay {
                VStack(alignment: .leading, spacing: 0) {
                    heroHeaderDashboard(disp)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            switch store.selectedTab {
                            case 0:
                                overviewAndScenesSection(disp)
                            case 1:
                                hiDPIAndResolutionSection(disp)
                            case 2:
                                xdrAndGammaCurveSection(disp)
                            case 3:
                                colorAndDeepHardwareSection(disp)
                            case 4:
                                iconAntiAliasingSection(disp)
                            case 5:
                                virtualAndDDCHardwareSection(disp)
                            default:
                                overviewAndScenesSection(disp)
                            }
                        }
                        .padding(18)
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
            } else {
                Text("未检测到活动显示器")
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 1020, minHeight: 700)
        .alert("HiDPI 系统配置结果", isPresented: $store.showOverrideAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(store.overrideInstallAlertMessage)
        }
    }

    // MARK: - Left Sidebar
    @ViewBuilder
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // App Brand Banner
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.indigo, .blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 34, height: 34)
                    Image(systemName: "display.2")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("MacDisplayPro")
                        .font(.system(size: 15, weight: .bold))
                    Text("v2.0 Pro Universal Studio")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: { store.refreshDisplays() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help("刷新显示器与硬件寄存器状态")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)

            // Connected Displays Section
            Text("连接的显示器 (\(store.displays.count))")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)

            VStack(spacing: 6) {
                ForEach(store.displays) { disp in
                    let isSelected = (store.selectedDisplayID == disp.id)
                    Button(action: { store.selectedDisplayID = disp.id }) {
                        HStack(spacing: 10) {
                            Image(systemName: disp.isVirtual ? "rectangle.on.rectangle.dashed" : (disp.isBuiltin ? "laptopcomputer" : "display"))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isSelected ? .white : (disp.isVirtual ? .purple : .indigo))
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(disp.name)
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundColor(isSelected ? .white : .primary)
                                Text("\(disp.currentMode?.resolutionText ?? "未知") • \(disp.currentMode?.isHiDPI == true ? "HiDPI 2x" : "1x")")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                            }
                            Spacer()
                            if disp.supportsDDC {
                                Circle()
                                    .fill(isSelected ? Color.white : Color.green)
                                    .frame(width: 7, height: 7)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color.indigo : Color.secondary.opacity(0.08))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)

            Divider()
                .padding(.horizontal, 12)

            // 6 Pro Studio Navigation Modules
            Text("功能工作台")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 14)

            VStack(spacing: 4) {
                ForEach(navItems, id: \.tag) { item in
                    let active = (store.selectedTab == item.tag)
                    Button(action: { store.selectedTab = item.tag }) {
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(active ? item.tint : item.tint.opacity(0.14))
                                    .frame(width: 28, height: 28)
                                Image(systemName: item.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(active ? .white : item.tint)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title)
                                    .font(.system(size: 12.5, weight: active ? .bold : .medium))
                                    .foregroundColor(active ? .primary : .primary.opacity(0.85))
                                Text(item.subtitle)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(active ? item.tint.opacity(0.14) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Bottom Hardware Status Card
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 7, height: 7)
                    Text(DDCController.shared.architectureName)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                Text(store.statusMessage)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.08)))
            .padding(12)
        }
    }

    // MARK: - Top Hero Telemetry Dashboard
    @ViewBuilder
    private func heroHeaderDashboard(_ disp: ManagedDisplay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(disp.name)
                            .font(.system(size: 20, weight: .bold))
                        Text("\(disp.vendorHex):\(disp.modelHex)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        if let cur = disp.currentMode, store.isFavoriteMode(cur, for: disp) {
                            Label("常用默认 (\(cur.resolutionText)) 已生效", systemImage: "star.fill")
                                .font(.system(size: 10.5, weight: .bold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(Color.yellow.opacity(0.2)))
                                .foregroundColor(.orange)
                        }
                        Label("双向实时同步已开启", systemImage: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                            .foregroundColor(.green)
                    }
                    if let profile = store.smartProfiles[disp.id] {
                        Text(profile.summaryReport)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        store.lockCurrentAsDefault(for: disp.id)
                    }) {
                        Label("锁定当前为默认", systemImage: "pin.fill")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button(action: {
                        let msg = iconOptimizer.performOneClickAntiAliasingFix(for: disp)
                        store.statusMessage = msg
                        store.refreshDisplays()
                    }) {
                        Label("消除图标锯齿", systemImage: "sparkles.tv")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)

                    Button(action: {
                        store.performSmartAutoAdapt(for: disp.id)
                    }) {
                        Label("智能自动适配", systemImage: "wand.and.stars")
                            .font(.system(size: 11.5, weight: .bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
            }

            // 4 Live Hardware Telemetry Metric Cards
            HStack(spacing: 10) {
                let ppiDetail: String = {
                    if let tel = colorEngine.telemetry[disp.id], tel.calculatedPPI > 10 {
                        return "\(String(format: "%.1f", tel.physicalDiagonalInches)) 吋 • \(Int(tel.calculatedPPI)) PPI"
                    }
                    return "比例 \(disp.currentMode?.aspectRatioText ?? "16:9") @ \(disp.currentMode?.refreshRateText ?? "60 Hz")"
                }()
                MetricBadgeCard(
                    icon: "viewfinder",
                    tint: .indigo,
                    label: "当前逻辑分辨率",
                    value: disp.currentMode?.resolutionText ?? "2048 × 1152",
                    detail: ppiDetail
                )
                MetricBadgeCard(
                    icon: "square.stack.3d.up.fill",
                    tint: .blue,
                    label: "2x 视网膜合成缓冲",
                    value: "\(disp.currentMode?.pixelWidth ?? 4096) × \(disp.currentMode?.pixelHeight ?? 2304)",
                    detail: (disp.currentMode?.isHiDPI ?? true) ? "Scale 2.0x Retina 激活" : "原生 1.0x 缓冲"
                )
                MetricBadgeCard(
                    icon: "cpu.fill",
                    tint: .orange,
                    label: "当前屏幕色深",
                    value: (colorEngine.selectedBitDepth[disp.id] ?? .bit16).title,
                    detail: (colorEngine.selectedBitDepth[disp.id] ?? .bit16).subtitle
                )
                MetricBadgeCard(
                    icon: "paintpalette.fill",
                    tint: .pink,
                    label: "ColorSync 色彩配置",
                    value: colorEngine.activeProfileURL[disp.id]?.deletingPathExtension().lastPathComponent ?? "出厂原生 ICC",
                    detail: disp.supportsDDC ? "DDC/CI I²C 硬件直连已就绪" : "软件 LUT 管线"
                )
            }

            // Automation Toggles Bar
            HStack(spacing: 18) {
                Toggle("开机自启并静默恢复默认设置", isOn: $store.launchAtLogin)
                    .font(.system(size: 11, weight: .medium))
                Toggle("热插拔/唤醒时自动恢复最佳模式", isOn: $store.autoAdaptOnConnect)
                    .font(.system(size: 11, weight: .medium))
                Toggle("昼夜节律自动调节亮度与护眼色温", isOn: $store.autoCircadianEnabled)
                    .font(.system(size: 11, weight: .medium))
                Toggle("接管 Mac 键盘原生亮度/音量键", isOn: $store.mediaKeysInterceptEnabled)
                    .font(.system(size: 11, weight: .medium))
                Spacer()
            }
            .toggleStyle(.checkbox)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.65))
    }

    // MARK: - Section 0: Overview & Smart Workspace Scenes
    @ViewBuilder
    private func overviewAndScenesSection(_ disp: ManagedDisplay) -> some View {
        // 1. One-Click Smart Workspace Scene Cards
        ProCard(
            title: "一键智能工作情景模式 (Smart Workspace Scenes)",
            subtitle: "同时联动 HiDPI 分辨率、DDC 物理亮度/对比度、ColorSync 色彩配置、16-bit FP16 色深与硬件白平衡",
            icon: "sparkles.rectangle.stack.fill",
            iconColor: .indigo,
            badgeText: "5 大场景预设"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(SmartScenePreset.allScenes) { scene in
                    Button(action: {
                        store.applySmartScene(scene, for: disp.id)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: scene.icon)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(scene.tint)
                                Text(scene.title)
                                    .font(.system(size: 12.5, weight: .bold))
                                Spacer()
                            }
                            Text(scene.subtitle)
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .padding(11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(scene.tint.opacity(0.10))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .stroke(scene.tint.opacity(0.28), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        // 2. Visual HiDPI Scale Grid
        ProCard(
            title: "HiDPI 2x 视网膜缩放快速切换面板",
            subtitle: "所有档位均严格校验双倍像素帧缓冲 (backingScaleFactor = 2.0)，点击卡片右上角 ★ 星标可将任意分辨率设为当前屏幕的常用默认项",
            icon: "viewfinder",
            iconColor: .blue,
            badgeText: "\(disp.hiDPIModes.count) 个 2x Retina 档位"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(disp.hiDPIModes.prefix(9)) { mode in
                    let isFav = store.isFavoriteMode(mode, for: disp)
                    let tag: String? = isFav ? "常用默认" : (mode.width == 2048 ? "1.07x 黄金大视野" : (mode.width == 2304 ? "1.2x 均衡视野" : (mode.width == 2560 ? "5K 大视野" : nil)))
                    ResolutionScaleCard(
                        mode: mode,
                        isFavoriteDefault: isFav,
                        tagLabel: tag,
                        onSelect: { store.switchResolution(mode) },
                        onToggleFavorite: { store.toggleFavoriteMode(mode, for: disp) }
                    )
                }
            }
        }

        // 3. Quick Dual Hardware Brightness & Color Bar
        HStack(spacing: 14) {
            ProCard(
                title: "DDC/CI 硬件亮度与音量直控",
                subtitle: "通过 Apple Silicon IOAVService / Intel I²C 总线直接驱动显示器控制板",
                icon: "sun.max.fill",
                iconColor: .yellow,
                badgeText: "VCP 0x10 / 0x62"
            ) {
                VStack(spacing: 10) {
                    HStack {
                        Text("硬件亮度")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { store.ddcBrightness[disp.id] ?? 80 },
                                set: { store.setHardwareBrightness(for: disp.id, value: $0) }
                            ),
                            in: 0...100
                        )
                        Text("\(Int(store.ddcBrightness[disp.id] ?? 80))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                    }
                    HStack {
                        Text("硬件对比度")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { store.ddcContrast[disp.id] ?? 72 },
                                set: { store.setHardwareContrast(for: disp.id, value: $0) }
                            ),
                            in: 0...100
                        )
                        Text("\(Int(store.ddcContrast[disp.id] ?? 72))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                    }
                    HStack {
                        Text("硬件音量")
                            .font(.system(size: 12, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Slider(
                            value: Binding(
                                get: { store.ddcVolume[disp.id] ?? 50 },
                                set: { store.setHardwareVolume(for: disp.id, value: $0) }
                            ),
                            in: 0...100
                        )
                        Text("\(Int(store.ddcVolume[disp.id] ?? 50))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .frame(width: 42, alignment: .trailing)
                    }
                }
            }

            ProCard(
                title: "屏幕色彩配置文件快捷切换 (ColorSync)",
                subtitle: "一键在 Display P3、sRGB、显示器原生配置与影视色域间无损切换",
                icon: "paintpalette.fill",
                iconColor: .pink,
                badgeText: "ICC 实时生效"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(colorEngine.availableProfiles.prefix(6)) { prof in
                            let isCurrent = colorEngine.isProfileActive(prof, for: disp.id)
                            Button(action: {
                                let res = colorEngine.applyColorProfile(prof, for: disp.id)
                                store.statusMessage = res.message
                                HUDManager.shared.show(icon: "paintpalette.fill", title: "已切换色彩配置", subtitle: prof.name, tint: .pink)
                            }) {
                                HStack {
                                    Text(prof.name)
                                        .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                                        .lineLimit(1)
                                    Spacer()
                                    if isCurrent {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.pink)
                                            .font(.system(size: 11))
                                    }
                                }
                                .padding(.horizontal, 9)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(isCurrent ? Color.pink.opacity(0.16) : Color.secondary.opacity(0.08))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 1: HiDPI & Custom Resolution Generator
    @ViewBuilder
    private func hiDPIAndResolutionSection(_ disp: ManagedDisplay) -> some View {
        ProCard(
            title: "HiDPI (2x Retina) 视网膜模式矩阵",
            subtitle: "点击任一卡片立即切换，无需重启系统",
            icon: "viewfinder.rectangular",
            iconColor: .blue,
            badgeText: "共 \(disp.hiDPIModes.count) 项"
        ) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(disp.hiDPIModes) { mode in
                    let isFav = store.isFavoriteMode(mode, for: disp)
                    ResolutionScaleCard(
                        mode: mode,
                        isFavoriteDefault: isFav,
                        tagLabel: isFav ? "常用默认" : nil,
                        onSelect: { store.switchResolution(mode) },
                        onToggleFavorite: { store.toggleFavoriteMode(mode, for: disp) }
                    )
                }
            }
        }

        HStack(alignment: .top, spacing: 14) {
            ProCard(
                title: "方式 A: 零重启虚拟 HiDPI 镜像引擎",
                subtitle: "为不支持原生 HiDPI 的 1080p/2K/带鱼屏创建 2x Retina 虚拟主屏并硬件镜像",
                icon: "bolt.horizontal.circle.fill",
                iconColor: .indigo,
                badgeText: "免重启黑科技"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("当你连接任何非 4K 外接显示器（如在 2019 MacBook Pro 上外接 2K 显示器）时，点击下方按钮即可在不修改系统 SIP 文件、不重启的情况下立即获得全套 2x HiDPI 清晰缩放：")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button("开启 2048×1152 黄金 HiDPI 镜像") {
                            let ok = virtualManager.enableZeroRebootHiDPIMirror(
                                forPhysicalDisplay: disp.id,
                                physicalName: disp.name,
                                targetScaledWidth: 2048,
                                targetScaledHeight: 1152
                            )
                            store.statusMessage = ok ? "已激活 2048×1152 零重启虚拟 HiDPI 镜像！" : "创建虚拟镜像失败"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.refreshDisplays() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)

                        Button("开启 2560×1440 2K HiDPI 镜像") {
                            let ok = virtualManager.enableZeroRebootHiDPIMirror(
                                forPhysicalDisplay: disp.id,
                                physicalName: disp.name,
                                targetScaledWidth: 2560,
                                targetScaledHeight: 1440
                            )
                            store.statusMessage = ok ? "已激活 2K 零重启虚拟 HiDPI 镜像！" : "创建虚拟镜像失败"
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.refreshDisplays() }
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            ProCard(
                title: "方式 B: 系统级 EDID Override Plist 注入器",
                subtitle: HiDPIManager.shared.systemOverrideFilePath(vendorID: disp.vendorID, modelID: disp.modelID),
                icon: "doc.badge.gearshape",
                iconColor: .teal,
                badgeText: "原生 scale-resolutions"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach($store.customHiDPIPresets) { $preset in
                        Toggle(isOn: $preset.enabled) {
                            Text("\(preset.label) → 2x 缓冲 \(preset.scaledWidth * 2)×\(preset.scaledHeight * 2)")
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                    }

                    HStack {
                        TextField("宽 (如 2304)", text: $store.newHiDPIWidth)
                            .frame(width: 85)
                            .textFieldStyle(.roundedBorder)
                        Text("×")
                        TextField("高 (如 1296)", text: $store.newHiDPIHeight)
                            .frame(width: 85)
                            .textFieldStyle(.roundedBorder)
                        Button("添加自定义分辨率") {
                            if let w = Int(store.newHiDPIWidth), let h = Int(store.newHiDPIHeight), w >= 800, h >= 600 {
                                store.customHiDPIPresets.append(
                                    CustomHiDPIPreset(scaledWidth: w, scaledHeight: h, label: "\(w) × \(h) (自定义 2x HiDPI)", enabled: true)
                                )
                            }
                        }
                        .controlSize(.small)
                    }

                    HStack(spacing: 10) {
                        Button("生成 Plist 预览") {
                            let activeRes = store.customHiDPIPresets.filter { $0.enabled }.map { ($0.scaledWidth, $0.scaledHeight) }
                            store.generatedPlistPreview = HiDPIManager.shared.generateOverridePlistXML(
                                displayName: disp.name,
                                vendorID: disp.vendorID,
                                modelID: disp.modelID,
                                resolutions: activeRes
                            )
                        }
                        Button("一键写入系统 Overrides 目录") {
                            let activeRes = store.customHiDPIPresets.filter { $0.enabled }.map { ($0.scaledWidth, $0.scaledHeight) }
                            let res = HiDPIManager.shared.installSystemHiDPIOverride(
                                displayName: disp.name,
                                vendorID: disp.vendorID,
                                modelID: disp.modelID,
                                resolutions: activeRes
                            )
                            store.overrideInstallAlertMessage = res.message
                            store.showOverrideAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: XDR Boost, Live Gamma LUT Curve & Eye-Care
    @ViewBuilder
    private func xdrAndGammaCurveSection(_ disp: ManagedDisplay) -> some View {
        let factor = store.xdrLuminanceFactor[disp.id] ?? 1.0
        let warmth = store.warmthFactor[disp.id] ?? 0.0

        HStack(alignment: .top, spacing: 14) {
            ProCard(
                title: "XDR 高光提亮与夜间暗光引擎 (零白屏硬件 LUT 架构)",
                subtitle: "采用 1×1 隐形 EDR 信标 + 256 级 16-bit GPU 硬件伽马曲线增益，彻底杜绝全屏泛白",
                icon: "sun.max.trianglebadge.exclamationmark",
                iconColor: .orange,
                badgeText: "\(Int(factor * 100))%"
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("全屏亮度增益倍率:")
                            .font(.system(size: 12.5, weight: .bold))
                        Spacer()
                        Text(factor > 1.01 ? "🔥 XDR 硬件 LUT 高光增益 (\(Int(factor * 100))%)" : (factor < 0.99 ? "🌙 夜间暗光遮罩 (\(Int(factor * 100))%)" : "☀️ 100% 原生标准 SDR"))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(factor > 1.01 ? .orange : .primary)
                    }

                    Slider(
                        value: Binding(
                            get: { store.xdrLuminanceFactor[disp.id] ?? 1.0 },
                            set: { store.setXDRLuminance(for: disp.id, factor: $0) }
                        ),
                        in: 0.15...2.30
                    )

                    HStack(spacing: 8) {
                        Button("35% 深夜极暗") { store.setXDRLuminance(for: disp.id, factor: 0.35) }
                        Button("70% 柔和暗光") { store.setXDRLuminance(for: disp.id, factor: 0.70) }
                        Button("100% 原生标准") { store.setXDRLuminance(for: disp.id, factor: 1.0) }
                            .buttonStyle(.borderedProminent)
                        Button("145% HDR 提亮") { store.setXDRLuminance(for: disp.id, factor: 1.45) }
                        Button("190% XDR 超亮") { store.setXDRLuminance(for: disp.id, factor: 1.90) }
                        Button("重置 LUT") {
                            colorEngine.resetDisplayTransferTable(for: disp.id)
                            store.xdrLuminanceFactor[disp.id] = 1.0
                            store.warmthFactor[disp.id] = 0.0
                            store.statusMessage = "已重置 GPU 硬件 LUT 伽马表至系统原生默认"
                        }
                    }
                    .controlSize(.small)

                    Divider()

                    HStack {
                        Text("护眼暖色温滤镜 (减少蓝光刺激):")
                            .font(.system(size: 12.5, weight: .bold))
                        Spacer()
                        Text("\(Int(warmth * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    Slider(
                        value: Binding(
                            get: { store.warmthFactor[disp.id] ?? 0.0 },
                            set: { store.setWarmth(for: disp.id, warmth: $0) }
                        ),
                        in: 0.0...1.0
                    )
                    HStack(spacing: 8) {
                        Button("0% 标准 6500K") { store.setWarmth(for: disp.id, warmth: 0.0) }
                        Button("25% 轻度阅读暖光") { store.setWarmth(for: disp.id, warmth: 0.25) }
                        Button("55% 深夜琥珀护眼") { store.setWarmth(for: disp.id, warmth: 0.55) }
                    }
                    .controlSize(.small)
                }
            }

            ProCard(
                title: "GPU 256 级硬件 LUT 实时响应曲线",
                subtitle: "横轴为输入像素灰度 (0~255)，纵轴为硬件管线输出亮度",
                icon: "waveform.path.ecg",
                iconColor: .cyan,
                badgeText: "16-bit LUT"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    GammaCurveVisualizer(factor: factor, warmth: warmth)
                        .frame(height: 175)

                    HStack {
                        Label("橙青线: 主亮度增益曲线 (暗部锚定 0 防泛白)", systemImage: "line.diagonal")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                        Spacer()
                        if warmth > 0.01 {
                            Label("蓝线: 蓝光抑制通道", systemImage: "line.diagonal")
                                .font(.system(size: 10.5))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .frame(width: 340)
        }
    }

    // MARK: - Section 3: ColorSync ICC Profiles & 12-bit / FP16 Deep Hardware
    @ViewBuilder
    private func colorAndDeepHardwareSection(_ disp: ManagedDisplay) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ProCard(
                title: "屏幕色彩配置文件管理 (ColorSync ICC Profiles)",
                subtitle: "直接调用 macOS ColorSyncDeviceSetCustomProfiles 实时切换色域映射",
                icon: "paintpalette.fill",
                iconColor: .pink,
                badgeText: colorEngine.activeProfileURL[disp.id]?.lastPathComponent ?? "Factory Default"
            ) {
                VStack(spacing: 6) {
                    ForEach(colorEngine.availableProfiles) { prof in
                        let isCurrent = colorEngine.isProfileActive(prof, for: disp.id)
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(prof.name)
                                        .font(.system(size: 12.5, weight: .bold))
                                    if prof.isRecommended {
                                        Text("推荐")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1)
                                            .background(Color.pink.opacity(0.18))
                                            .foregroundColor(.pink)
                                            .cornerRadius(4)
                                    }
                                }
                                Text(prof.subtitle)
                                    .font(.system(size: 10.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if isCurrent {
                                Label("当前生效", systemImage: "checkmark.seal.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.green)
                            } else {
                                Button("立即应用") {
                                    let res = colorEngine.applyColorProfile(prof, for: disp.id)
                                    store.statusMessage = res.message
                                    HUDManager.shared.show(icon: "paintpalette.fill", title: "色彩配置已切换", subtitle: prof.name, tint: .pink)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.pink)
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(isCurrent ? Color.pink.opacity(0.10) : Color.secondary.opacity(0.05)))
                    }
                }
            }

            VStack(spacing: 14) {
                ProCard(
                    title: "屏幕色深档位选择 (Bit Depth)",
                    subtitle: "一键选择屏幕色深精度（已内置硬件级防断层稳定锁）",
                    icon: "cpu.fill",
                    iconColor: .orange,
                    badgeText: (colorEngine.selectedBitDepth[disp.id] ?? .bit16).title
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            ForEach(BitDepthChoice.allCases) { choice in
                                let isSelected = (colorEngine.selectedBitDepth[disp.id] ?? .bit16) == choice
                                Button(action: {
                                    store.statusMessage = colorEngine.selectBitDepth(choice, for: disp.id)
                                    HUDManager.shared.show(
                                        icon: "cpu.fill",
                                        title: "已切换至 \(choice.title)",
                                        subtitle: choice.subtitle,
                                        tint: .orange
                                    )
                                }) {
                                    VStack(spacing: 5) {
                                        Text(choice.title)
                                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                                            .foregroundColor(isSelected ? .white : .primary)
                                        Text(choice.subtitle)
                                            .font(.system(size: 10))
                                            .foregroundColor(isSelected ? .white.opacity(0.9) : .secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .fill(isSelected ? Color.orange : Color.secondary.opacity(0.08))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .stroke(isSelected ? Color.orange : Color.primary.opacity(0.08), lineWidth: 1.5)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Built-in Dark Gradient Anti-Banding Test Strip
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("深色阶渐变断层测试条 (观察暗部过渡是否丝滑无条纹):")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text("1024级 16-bit LUT FRC 抖动已激活")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.orange)
                            }
                            RoundedRectangle(cornerRadius: 6)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            Color(red: 0.01, green: 0.01, blue: 0.02),
                                            Color(red: 0.05, green: 0.07, blue: 0.12),
                                            Color(red: 0.12, green: 0.16, blue: 0.26),
                                            Color(red: 0.25, green: 0.32, blue: 0.48)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(height: 24)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                                )
                        }

                        // Dynamic Display Output Link Descriptions & Hardware Slot Switcher
                        Divider()
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("底层输出硬件链路模式 (Display Output Link):")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Toggle("SDR 模式自动锁定 RGB 4:4:4", isOn: Binding(
                                    get: { store.isAutoGuardRGB444Enabled(for: disp) },
                                    set: { store.setAutoGuardRGB444(for: disp, enabled: $0) }
                                ))
                                .toggleStyle(.checkbox)
                                .font(.system(size: 10.5))
                            }

                            if let linkModes = colorEngine.availableLinkModes[disp.id], !linkModes.isEmpty {
                                VStack(spacing: 5) {
                                    ForEach(linkModes) { lMode in
                                        HStack(spacing: 8) {
                                            Text("[\(lMode.index)]")
                                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                                .foregroundColor(.secondary)
                                                .frame(width: 24, alignment: .leading)

                                            VStack(alignment: .leading, spacing: 1) {
                                                HStack(spacing: 5) {
                                                    Text("\(lMode.bitDepth)-Bit \(lMode.encodingText)")
                                                        .font(.system(size: 11, weight: .bold))
                                                    Text(lMode.rangeText)
                                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(Color.secondary.opacity(0.12))
                                                        .cornerRadius(3)
                                                    Text(lMode.eotfText)
                                                        .font(.system(size: 9.5, weight: .bold))
                                                        .padding(.horizontal, 4)
                                                        .padding(.vertical, 1)
                                                        .background(lMode.isHDR ? Color.purple.opacity(0.18) : Color.blue.opacity(0.15))
                                                        .foregroundColor(lMode.isHDR ? .purple : .blue)
                                                        .cornerRadius(3)
                                                    if lMode.isRGB444 && lMode.isFullRange {
                                                        Text("高保真零毛边")
                                                            .font(.system(size: 9, weight: .bold))
                                                            .padding(.horizontal, 4)
                                                            .padding(.vertical, 1)
                                                            .background(Color.green.opacity(0.18))
                                                            .foregroundColor(.green)
                                                            .cornerRadius(3)
                                                    }
                                                }
                                            }

                                            Spacer()

                                            if lMode.isActive {
                                                Label("当前生效", systemImage: "checkmark.circle.fill")
                                                    .font(.system(size: 10.5, weight: .bold))
                                                    .foregroundColor(.green)
                                            } else {
                                                Button("应用") {
                                                    let res = colorEngine.switchLinkModeByIndex(for: disp.id, index: lMode.index)
                                                    store.statusMessage = res
                                                    HUDManager.shared.show(
                                                        icon: "display",
                                                        title: "已切换链路 [\(lMode.index)]",
                                                        subtitle: lMode.summaryText,
                                                        tint: lMode.isRGB444 ? .green : .purple
                                                    )
                                                }
                                                .buttonStyle(.bordered)
                                                .controlSize(.mini)
                                            }
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(lMode.isActive ? Color.green.opacity(0.08) : Color.secondary.opacity(0.04)))
                                    }
                                }
                            } else {
                                let tel = colorEngine.telemetry[disp.id]
                                let isSlot1 = (tel?.activeLinkBitDepth == 12 && tel?.activeEOTF == 2)
                                let isSlot4 = (tel?.activePixelEncoding == 0 && tel?.activeDynamicRange == 1 && tel?.activeEOTF == 0)
                                HStack(spacing: 8) {
                                    Button(action: {
                                        let msg = colorEngine.activateLinkSlot1_12BitHDR10(for: disp.id)
                                        store.statusMessage = msg
                                        HUDManager.shared.show(icon: "sparkles.tv.fill", title: "已开启 [1] 12-bit HDR10", subtitle: "EOTF=2 • YCbCr 4:2:2 • Limited", tint: .purple)
                                    }) {
                                        Label(isSlot1 ? "✅ [1] 12-bit HDR10 已激活" : "开启 [1] 12-bit HDR10", systemImage: "bolt.horizontal.fill")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isSlot1 ? .purple : .secondary)
                                    .controlSize(.small)

                                    Button(action: {
                                        let msg = colorEngine.activateLinkSlot4_RGB444FullRange(for: disp.id)
                                        store.statusMessage = msg
                                        HUDManager.shared.show(icon: "checkmark.shield.fill", title: "已恢复 [4] Pure RGB 4:4:4", subtitle: "Full Range 0-255 • SDR 零毛边", tint: .green)
                                    }) {
                                        Label(isSlot4 ? "✅ [4] Pure RGB 4:4:4 已激活" : "恢复 [4] Pure RGB 4:4:4", systemImage: "display")
                                            .font(.system(size: 11, weight: .semibold))
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(isSlot4 ? .green : .secondary)
                                    .controlSize(.small)
                                }
                            }

                            HStack {
                                Button("重置色彩与伽马查找表 (恢复 ColorSync 默认)") {
                                    colorEngine.resetDisplayTransferTable(for: disp.id)
                                    store.statusMessage = "已重置色彩查找表并恢复 ColorSync 原生伽马"
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                Spacer()
                            }
                        }
                    }
                }

                ProCard(
                    title: "DDC/CI 硬件级 RGB 三原色独立增益调校",
                    subtitle: "直接调节显示器驱动板 R(0x16) / G(0x18) / B(0x1A) 硬件电压增益",
                    icon: "slider.vertical.3",
                    iconColor: .indigo,
                    badgeText: "硬件白平衡"
                ) {
                    let r = colorEngine.redGain[disp.id] ?? 100
                    let g = colorEngine.greenGain[disp.id] ?? 100
                    let b = colorEngine.blueGain[disp.id] ?? 100
                    VStack(spacing: 8) {
                        HStack {
                            Text("🔴 红色增益 (0x16)").font(.system(size: 11.5)).frame(width: 115, alignment: .leading)
                            Slider(value: Binding(get: { r }, set: { colorEngine.setHardwareRGBGain(for: disp.id, r: $0, g: g, b: b) }), in: 0...100)
                            Text("\(Int(r))").font(.system(size: 11, design: .monospaced)).frame(width: 30)
                        }
                        HStack {
                            Text("🟢 绿色增益 (0x18)").font(.system(size: 11.5)).frame(width: 115, alignment: .leading)
                            Slider(value: Binding(get: { g }, set: { colorEngine.setHardwareRGBGain(for: disp.id, r: r, g: $0, b: b) }), in: 0...100)
                            Text("\(Int(g))").font(.system(size: 11, design: .monospaced)).frame(width: 30)
                        }
                        HStack {
                            Text("🔵 蓝色增益 (0x1A)").font(.system(size: 11.5)).frame(width: 115, alignment: .leading)
                            Slider(value: Binding(get: { b }, set: { colorEngine.setHardwareRGBGain(for: disp.id, r: r, g: g, b: $0) }), in: 0...100)
                            Text("\(Int(b))").font(.system(size: 11, design: .monospaced)).frame(width: 30)
                        }
                        HStack(spacing: 8) {
                            Button("6500K D65 标准") { colorEngine.setHardwareRGBGain(for: disp.id, r: 100, g: 100, b: 100, force: true) }
                            Button("7500K 通透冷白") { colorEngine.setHardwareRGBGain(for: disp.id, r: 94, g: 97, b: 100, force: true) }
                            Button("5800K 柔和原彩") { colorEngine.setHardwareRGBGain(for: disp.id, r: 100, g: 96, b: 88, force: true) }
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - Section 4: App Icon & Font Anti-Aliasing Lab
    @ViewBuilder
    private func iconAntiAliasingSection(_ disp: ManagedDisplay) -> some View {
        ProCard(
            title: "一键全链路修复 App 图标与 UI 边缘锯齿",
            subtitle: "解决切换分辨率后 Dock 图标残留 @1x 低清位图缓存、显示器 VCP 0x87 过锐白边与次像素阶梯伪影",
            icon: "sparkles.tv",
            iconColor: .teal,
            badgeText: "Retina @2x 矢量重建"
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    Button(action: {
                        let msg = iconOptimizer.performOneClickAntiAliasingFix(for: disp, switchToPixelPerfect2x: false)
                        store.statusMessage = msg
                        HUDManager.shared.show(icon: "sparkles.tv", title: "图标去毛边已完成", subtitle: "已对齐 64pt (120px) 整数像素网格", tint: .teal)
                    }) {
                        Label("✨ 一键消除图标毛边 (整数像素网格对齐 + 重建 @2x 缓存 + 锐度校准)", systemImage: "wand.and.rays")
                            .padding(.vertical, 3)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.teal)

                    Button("48pt 紧凑无毛边 (90px)") {
                        iconOptimizer.alignDockToHarmonicPixelGrid(tileSizePt: 48)
                        iconOptimizer.rebuildRetinaIconAndDockCache()
                        store.statusMessage = "已锁定 Dock 图标为 48pt (96px @2x → 90.0 整数物理像素)"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("56pt 适中无毛边 (105px)") {
                        iconOptimizer.alignDockToHarmonicPixelGrid(tileSizePt: 56)
                        iconOptimizer.rebuildRetinaIconAndDockCache()
                        store.statusMessage = "已锁定 Dock 图标为 56pt (112px @2x → 105.0 整数物理像素)"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("64pt 完美2x无毛边 (120px)") {
                        iconOptimizer.alignDockToHarmonicPixelGrid(tileSizePt: 64)
                        iconOptimizer.rebuildRetinaIconAndDockCache()
                        store.statusMessage = "已锁定 Dock 图标为 64pt (128px @2x → 120.0 整数物理像素，零初次缩放)"
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("恢复系统默认 Dock") {
                        iconOptimizer.restoreDefaultDockPreferences()
                        store.statusMessage = "已清除 Dock 图标尺寸覆盖，恢复 macOS 系统默认"
                        HUDManager.shared.show(icon: "arrow.counterclockwise", title: "Dock 恢复默认", subtitle: "已重置为系统默认配置", tint: .teal)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(iconOptimizer.lastOptimizationLog)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.teal)
            }
        }

        HStack(alignment: .top, spacing: 14) {
            ProCard(
                title: "显示器硬件锐度去锯齿校准 (DDC VCP 0x87)",
                subtitle: "将显示器内部超分锐度设为 50% 可彻底消除圆角图标周围的锯齿状白边",
                icon: "dial.medium.fill",
                iconColor: .blue,
                badgeText: "\(Int(iconOptimizer.hardwareSharpness[disp.id] ?? 50))%"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Slider(
                        value: Binding(
                            get: { iconOptimizer.hardwareSharpness[disp.id] ?? 50 },
                            set: { iconOptimizer.setHardwareSharpness(for: disp.id, value: $0) }
                        ),
                        in: 0...100
                    )
                    HStack(spacing: 8) {
                        Button("50% 标准无锯齿白边 (推荐)") {
                            iconOptimizer.setHardwareSharpness(for: disp.id, value: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("40% 柔和边缘") {
                            iconOptimizer.setHardwareSharpness(for: disp.id, value: 40)
                        }
                    }
                    .controlSize(.small)
                }
            }

            ProCard(
                title: "macOS Quartz 2D 矢量与字体平滑抗锯齿等级",
                subtitle: "配置 AppleFontSmoothing 全局次像素/灰度平滑强度",
                icon: "textformat.abc",
                iconColor: .indigo,
                badgeText: "Level \(iconOptimizer.currentSmoothingLevel.rawValue)"
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SmoothingLevel.allCases) { lvl in
                        Button(action: {
                            iconOptimizer.applySmoothingLevel(lvl)
                            store.statusMessage = iconOptimizer.lastOptimizationLog
                        }) {
                            HStack {
                                Text(lvl.title)
                                    .font(.system(size: 11.5, weight: iconOptimizer.currentSmoothingLevel == lvl ? .bold : .regular))
                                Spacer()
                                if iconOptimizer.currentSmoothingLevel == lvl {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.indigo)
                                }
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 7).fill(iconOptimizer.currentSmoothingLevel == lvl ? Color.indigo.opacity(0.14) : Color.secondary.opacity(0.06)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Section 5: Virtual Displays, PiP & DDC Bus Debugger
    @ViewBuilder
    private func virtualAndDDCHardwareSection(_ disp: ManagedDisplay) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ProCard(
                title: "虚拟显示器工作台 (CGVirtualDisplay 引擎)",
                subtitle: "一键挂载任意分辨率与刷新率的 2x HiDPI 虚拟屏幕，支持画中画 (PiP) 悬浮预览",
                icon: "rectangle.stack.badge.plus",
                iconColor: .purple,
                badgeText: "已挂载 \(virtualManager.activeVirtualDisplays.count) 台"
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(VirtualDisplayTemplate.templates) { tpl in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tpl.title).font(.system(size: 12, weight: .bold))
                                Text(tpl.subtitle).font(.system(size: 10.5)).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("创建") {
                                _ = virtualManager.createVirtualDisplay(
                                    name: tpl.title,
                                    width: tpl.baseWidth,
                                    height: tpl.baseHeight,
                                    refreshRate: tpl.refreshRate,
                                    hiDPI: tpl.hiDPI
                                )
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { store.refreshDisplays() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.secondary.opacity(0.06)))
                    }

                    if !virtualManager.activeVirtualDisplays.isEmpty {
                        Divider()
                        ForEach(virtualManager.activeVirtualDisplays) { vDisp in
                            HStack {
                                Text("\(vDisp.name) (ID: \(vDisp.displayID))")
                                    .font(.system(size: 11.5, weight: .bold))
                                Spacer()
                                Button("画中画预览") { virtualManager.openPiPWindow(for: vDisp) }
                                    .controlSize(.small)
                                Button("断开") {
                                    virtualManager.removeVirtualDisplay(id: vDisp.id)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.refreshDisplays() }
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            ProCard(
                title: "DDC/CI 硬件信号源与底层 I²C 寄存器调试台",
                subtitle: "支持物理输入源一键切换 (VCP 0x60) 及任意 VESA MCCS VCP 指令读写",
                icon: "cpu",
                iconColor: .green,
                badgeText: "0x37 / 0x6E I²C"
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("一键切换显示器物理输入信号源 (VCP 0x60):")
                        .font(.system(size: 11.5, weight: .bold))
                    HStack(spacing: 6) {
                        ForEach(DDCInputSource.allCases) { src in
                            Button(src.label) {
                                store.switchInputSource(for: disp.id, input: src)
                            }
                            .controlSize(.small)
                            .buttonStyle(.bordered)
                        }
                    }

                    Divider()

                    Text("自定义 VCP 十六进制指令读写调试:")
                        .font(.system(size: 11.5, weight: .bold))
                    HStack(spacing: 8) {
                        Text("VCP (Hex):")
                        TextField("10", text: $store.customVCPHex)
                            .frame(width: 50)
                            .textFieldStyle(.roundedBorder)
                        Text("值 (Dec):")
                        TextField("80", text: $store.customVCPWriteValue)
                            .frame(width: 65)
                            .textFieldStyle(.roundedBorder)
                        Button("写入") {
                            let code = UInt8(store.customVCPHex, radix: 16) ?? 0x10
                            let val = UInt16(store.customVCPWriteValue) ?? 50
                            let ok = MDP_WriteDDCValue(disp.id, code, val)
                            store.customVCPReadOutput = ok ? "✅ 写入成功: 0x\(String(format: "%02X", code)) = \(val)" : "⚠️ 写入未收到 ACK"
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button("读取") {
                            let code = UInt8(store.customVCPHex, radix: 16) ?? 0x10
                            let res = MDP_ReadDDCValue(disp.id, code)
                            store.customVCPReadOutput = res.success
                                ? "✅ 读取成功: 当前值 = \(res.currentValue), 最大值 = \(res.maxValue)"
                                : "⚠️ 读取无回复 (0x\(String(format: "%02X", code)))"
                        }
                        .controlSize(.small)
                    }
                    Text(store.customVCPReadOutput)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
