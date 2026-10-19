import AppKit
import SwiftUI

enum AppLinks {
    static let author = "A2ureeE"
    static let repositoryURL = URL(string: "https://github.com/A2ureeE/CrazyAutoDL")!
    static let repositoryLabel = "github.com/A2ureeE/CrazyAutoDL"

    static func openRepository() {
        NSWorkspace.shared.open(repositoryURL)
    }
}

enum AppTheme {
    static let mint = Color(red: 0.38, green: 0.98, blue: 0.76)
    static let aqua = Color(red: 0.33, green: 0.81, blue: 1.00)
    static let violet = Color(red: 0.60, green: 0.51, blue: 1.00)
    static let amber = Color(red: 1.00, green: 0.76, blue: 0.34)
    static let rose = Color(red: 1.00, green: 0.45, blue: 0.52)
    static let textPrimary = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.57)
    static let textTertiary = Color.white.opacity(0.34)

    static let pageBackground = Color(red: 0.027, green: 0.055, blue: 0.062)

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [mint, aqua],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    static var coolGradient: LinearGradient {
        LinearGradient(
            colors: [aqua, violet],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension InstanceState {
    var tint: Color {
        switch self {
        case .running: return AppTheme.mint
        case .stopped: return Color.white.opacity(0.48)
        case .starting: return AppTheme.amber
        case .stopping: return AppTheme.rose
        case .unknown: return AppTheme.violet
        }
    }
}

extension ActivityKind {
    var tint: Color {
        switch self {
        case .info: return AppTheme.aqua
        case .success: return AppTheme.mint
        case .warning: return AppTheme.amber
        case .error: return AppTheme.rose
        }
    }
}

struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

struct AuroraBackground: View {
    @State private var drift = false

    var body: some View {
        ZStack {
            VisualEffectView()

            LinearGradient(
                colors: [
                    Color(red: 0.025, green: 0.07, blue: 0.078).opacity(0.94),
                    Color(red: 0.025, green: 0.048, blue: 0.085).opacity(0.92),
                    Color(red: 0.045, green: 0.035, blue: 0.075).opacity(0.94)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(AppTheme.mint.opacity(0.26))
                .frame(width: 620, height: 620)
                .blur(radius: 150)
                .offset(x: drift ? -330 : -390, y: drift ? -330 : -280)

            Circle()
                .fill(AppTheme.violet.opacity(0.30))
                .frame(width: 620, height: 620)
                .blur(radius: 170)
                .offset(x: drift ? 480 : 420, y: drift ? -240 : -150)

            Circle()
                .fill(AppTheme.aqua.opacity(0.16))
                .frame(width: 520, height: 520)
                .blur(radius: 150)
                .offset(x: drift ? 240 : 310, y: drift ? 420 : 370)

            GridTexture()
                .opacity(0.035)
                .mask(
                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )

            LinearGradient(
                colors: [.black.opacity(0.10), .black.opacity(0.30)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}

private struct GridTexture: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 44
            var x: CGFloat = 0
            while x < size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            context.stroke(path, with: .color(.white), lineWidth: 0.5)
        }
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            configure(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(nsView.window)
        }
    }

    private func configure(_ window: NSWindow?) {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 1_060, height: 720)
    }
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color
    var interactive: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular.tint(tint.opacity(0.20)).interactive(),
                        in: shape
                    )
                    .overlay(border)
                    .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 14)
            } else {
                content
                    .glassEffect(
                        .regular.tint(tint.opacity(0.16)),
                        in: shape
                    )
                    .overlay(border)
                    .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 14)
            }
        } else {
            content
                .background(.ultraThinMaterial, in: shape)
                .background(tint.opacity(0.05), in: shape)
                .overlay(border)
                .shadow(color: .black.opacity(0.22), radius: 26, x: 0, y: 14)
        }
    }

    private var border: some View {
        shape
            .strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(0.34),
                        .white.opacity(0.07),
                        tint.opacity(0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.8
            )
            .overlay(alignment: .topLeading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(width: 86, height: 1)
                    .blur(radius: 0.6)
                    .padding(.leading, 24)
                    .padding(.top, 1)
            }
            .allowsHitTesting(false)
    }
}

extension View {
    func glassPanel(
        cornerRadius: CGFloat = 28,
        tint: Color = .white,
        interactive: Bool = false
    ) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, tint: tint, interactive: interactive))
    }

    func panelBorder(cornerRadius: CGFloat = 28, tint: Color = .white) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.26), .white.opacity(0.05), tint.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.7
                )
                .allowsHitTesting(false)
        }
    }
}

enum AppBrand {
    static let icon: NSImage = {
        if let url = Bundle.main.url(forResource: "BrandIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSApplication.shared.applicationIconImage ?? NSImage(size: NSSize(width: 512, height: 512))
    }()
}

struct BrandMark: View {
    var size: CGFloat = 42

    var body: some View {
        Image(nsImage: AppBrand.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.38), radius: size * 0.2, x: 0, y: size * 0.09)
            .accessibilityLabel("胡闹AutoDL")
    }
}

struct StatusPill: View {
    let label: String
    let tint: Color
    var showsDot = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
                    .shadow(color: tint.opacity(0.8), radius: 4)
            }
            Text(label)
                .scaledFont(size: 11, weight: .semibold, design: .rounded)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.11), in: Capsule())
        .overlay {
            Capsule().strokeBorder(tint.opacity(0.26), lineWidth: 0.7)
        }
    }
}

struct GlassIconButton: View {
    let symbol: String
    let action: () -> Void
    var isActive = false
    var help: String = ""

    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(isActive ? AppTheme.mint : AppTheme.textSecondary)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
                .glassPanel(cornerRadius: 12, tint: isActive ? AppTheme.mint : .white, interactive: true)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            isActive ? AppTheme.mint.opacity(0.30) : .white.opacity(hovered ? 0.20 : 0.09),
                            lineWidth: 0.7
                        )
                }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) { hovered = hovering }
        }
        .help(help)
    }
}

private struct AppFontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    var appFontScale: CGFloat {
        get { self[AppFontScaleKey.self] }
        set { self[AppFontScaleKey.self] = newValue }
    }
}

private struct ScaledFontModifier: ViewModifier {
    @Environment(\.appFontScale) private var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design

    func body(content: Content) -> some View {
        content.font(.system(size: size * scale, weight: weight, design: design))
    }
}

extension View {
    func scaledFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, design: design))
    }
}

struct ActionButtonStyle: ButtonStyle {
    var tint: Color = .white
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaledFont(size: 12, weight: .semibold)
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background {
                if prominent {
                    Capsule().fill(
                        LinearGradient(
                            colors: [tint.opacity(0.98), tint.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                } else {
                    Capsule().fill(tint.opacity(0.09))
                }
            }
            .overlay {
                Capsule().strokeBorder(
                    prominent ? .white.opacity(0.40) : tint.opacity(0.22),
                    lineWidth: 0.7
                )
            }
            .shadow(
                color: prominent ? tint.opacity(0.28) : .clear,
                radius: 12,
                x: 0,
                y: 5
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct CustomSwitch: View {
    let isOn: Bool
    var tint: Color = AppTheme.mint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? tint.opacity(0.74) : Color.white.opacity(0.10))
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                isOn ? tint.opacity(0.45) : .white.opacity(0.13),
                                lineWidth: 0.8
                            )
                    }
                    .shadow(color: isOn ? tint.opacity(0.36) : .clear, radius: 12, x: 0, y: 3)

                Circle()
                    .fill(.white.opacity(0.98))
                    .overlay {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.white, .white.opacity(0.72)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }
                    .padding(3.5)
                    .shadow(color: .black.opacity(0.26), radius: 5, x: 0, y: 2)
            }
            .frame(width: 48, height: 27)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.36, dampingFraction: 0.78), value: isOn)
        .accessibilityLabel("自动开机")
        .accessibilityValue(isOn ? "已开启" : "已关闭")
    }
}

struct EyebrowLabel: View {
    let text: String
    var tint: Color = AppTheme.mint

    var body: some View {
        Text(text.uppercased())
            .scaledFont(size: 9, weight: .bold, design: .rounded)
            .tracking(1.8)
            .foregroundStyle(tint.opacity(0.82))
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .scaledFont(size: 28, weight: .light)
                .foregroundStyle(AppTheme.textSecondary)
            Text(title)
                .scaledFont(size: 15, weight: .semibold)
                .foregroundStyle(AppTheme.textPrimary)
            Text(message)
                .scaledFont(size: 12)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

enum AppFormat {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()

    static let fullDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()

    static func relative(_ date: Date?) -> String {
        guard let date else { return "尚未同步" }
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 { return "刚刚" }
        if seconds < 60 { return "\(seconds) 秒前" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) 分钟前" }
        return time.string(from: date)
    }

    static func storage(_ bytes: Int64) -> String {
        let gib = Double(max(0, bytes)) / 1_073_741_824
        if gib >= 1024 {
            return String(format: "%.2f TB", gib / 1024)
        }
        if gib >= 100 {
            return String(format: "%.0f GB", gib)
        }
        return String(format: "%.1f GB", gib)
    }
}
