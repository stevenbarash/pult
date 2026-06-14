import Foundation
import SwiftUI
import PultCore

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let alpha, red, green, blue: UInt64

        switch hex.count {
        case 3:
            (alpha, red, green, blue) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (alpha, red, green, blue) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (alpha, red, green, blue) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (alpha, red, green, blue) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255,
            opacity: Double(alpha) / 255
        )
    }

    /// Brand accent, applied at the app root so sheets inherit it too.
    static let pultAccent = PultDesign.accent
}

enum PultDesign {
    static let accent = Color(hex: "56D6C9")
    static let accentDeep = Color(hex: "178CA3")
    static let accentSoft = Color(hex: "D9FFF7")
    static let connected = Color(hex: "7BD99A")
    static let warning = Color(hex: "F2A65D")
    static let danger = Color(hex: "FF6A63")
    static let utility = Color(hex: "9FB8D9")

    static let carbonTop = Color(hex: "101416")
    static let carbonMid = Color(hex: "171D20")
    static let carbonBottom = Color(hex: "070A0C")
    static let warmInk = Color(hex: "F4FAF8")
    static let mutedInk = Color(hex: "AAB8B5")

    static let surface = Color.white.opacity(0.10)
    static let surfaceRaised = Color.white.opacity(0.16)
    static let surfaceStrong = Color.white.opacity(0.24)
    static let hairline = Color.white.opacity(0.14)
    static let hairlineStrong = Color.white.opacity(0.28)
}

enum PultTypography {
    static let display = Font.system(.largeTitle, design: .serif).weight(.bold)
    static let displaySmall = Font.system(.title2, design: .serif).weight(.bold)
    static let heading = Font.title3.weight(.semibold)
    static let subhead = Font.headline.weight(.semibold)
    static let body = Font.body
    static let bodySmall = Font.callout
    static let caption = Font.caption
    static let captionStrong = Font.caption.weight(.semibold)
}

enum PultSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum RemoteMetrics {
    static let keySize: CGFloat = 60
    static let clusterSpacing: CGFloat = 12
    static let surfaceCornerRadius: CGFloat = 36
    static let maxControlWidth: CGFloat = 430
}

struct PultMark: View {
    var size: CGFloat = 72
    var symbolName: String? = nil
    var tint: Color = .pultAccent

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        let cornerRadius = size * 0.24
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            shape
                .fill(backgroundGradient)
                .overlay {
                    shape
                        .stroke(.white.opacity(colorSchemeContrast == .increased ? 0.48 : 0.26), lineWidth: 1)
                }

            remoteGlyph

            if let symbolName {
                Image(systemName: symbolName)
                    .font(.system(size: size * 0.22, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(tint)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background {
                        Circle()
                            .fill(Color.black.opacity(reduceTransparency ? 0.72 : 0.48))
                    }
                    .offset(x: size * 0.24, y: size * 0.22)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: tint.opacity(reduceTransparency ? 0 : 0.28), radius: size * 0.14, y: size * 0.08)
        .accessibilityHidden(true)
    }

    private var backgroundGradient: LinearGradient {
        if reduceTransparency {
            return LinearGradient(
                colors: [
                    PultDesign.carbonMid,
                    PultDesign.carbonBottom
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                PultDesign.surfaceStrong,
                PultDesign.accent.opacity(0.72),
                PultDesign.accentDeep.opacity(0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var remoteGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                .fill(Color.black.opacity(reduceTransparency ? 0.74 : 0.58))
                .frame(width: size * 0.40, height: size * 0.66)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                        .stroke(.white.opacity(0.30), lineWidth: 1)
                }

            VStack(spacing: size * 0.07) {
                Circle()
                    .fill(PultDesign.warmInk.opacity(0.90))
                    .frame(width: size * 0.11, height: size * 0.11)

                ZStack {
                    Capsule()
                        .fill(tint)
                        .frame(width: size * 0.22, height: size * 0.07)
                    Capsule()
                        .fill(tint)
                        .frame(width: size * 0.07, height: size * 0.22)
                }

                HStack(spacing: size * 0.045) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(PultDesign.warmInk.opacity(0.76))
                            .frame(width: size * 0.06, height: size * 0.06)
                    }
                }
            }
        }
    }
}

struct PultBrandLockup: View {
    var subtitle: String? = nil
    var markSize: CGFloat = 54

    var body: some View {
        HStack(spacing: 12) {
            PultMark(size: markSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Pult")
                    .font(PultTypography.displaySmall)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(PultTypography.captionStrong)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct PultStatusChip: View {
    var title: String
    var systemImage: String
    var tint: Color
    var isProminent = false

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        Label {
            Text(title)
                .font(PultTypography.captionStrong)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .accessibilityHidden(true)
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(isProminent ? Color.primary : tint)
        .padding(.horizontal, 10)
        .frame(minHeight: 30)
        .background {
            Capsule()
                .fill(tint.opacity(colorSchemeContrast == .increased ? 0.26 : 0.15))
        }
        .overlay {
            Capsule()
                .stroke(tint.opacity(colorSchemeContrast == .increased ? 0.72 : 0.28), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct PultSheetHero: View {
    var systemImage: String
    var title: String
    var subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            PultMark(size: 54, symbolName: systemImage)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(PultTypography.displaySmall)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                Text(subtitle)
                    .font(PultTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .minimumScaleFactor(0.86)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PultSheetSectionHeader: View {
    var title: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(PultTypography.heading)
            if let detail {
                Text(detail)
                    .font(PultTypography.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A circular Liquid Glass remote key. Press haptics come from the surface's
/// shared key-press feedback, not from the button itself.
struct RemoteCircleButton: View {
    var systemImage: String
    var label: String
    var iconColor: Color?
    var size: CGFloat = RemoteMetrics.keySize
    var action: () -> Void

    var body: some View {
        let hitSize = max(size, 44)

        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.34, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(iconColor ?? .primary)
                .frame(width: size, height: size)
                .frame(width: hitSize, height: hitSize)
                .contentShape(.circle)
        }
        .buttonStyle(GlassShapeButtonStyle(shape: .circle))
        .accessibilityLabel(label)
    }
}

extension View {
    /// Adds an opaque backing and outline only when accessibility settings ask
    /// glass-heavy controls to carry more contrast.
    func pultGlassFallback<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        isProminent: Bool = false
    ) -> some View {
        modifier(PultGlassFallback(shape: shape, tint: tint, isProminent: isProminent))
    }

    /// A quiet content-layer backing for status, diagnostics, and banners.
    /// Use this instead of stacking glass beneath other glass controls.
    func pultContentSurface<S: Shape>(
        in shape: S,
        tint: Color? = nil,
        isProminent: Bool = false
    ) -> some View {
        modifier(PultContentSurface(shape: shape, tint: tint, isProminent: isProminent))
    }
}

private struct PultGlassFallback<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var isProminent: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var needsFallback: Bool {
        reduceTransparency || colorSchemeContrast == .increased
    }

    private var fallbackFill: Color {
        if let tint {
            return tint.opacity(reduceTransparency ? 0.34 : 0.22)
        }
        if colorScheme == .dark {
            return PultDesign.carbonMid.opacity(isProminent ? 0.95 : 0.78)
        }
        return Color.white.opacity(isProminent ? 0.94 : 0.84)
    }

    private var fallbackStroke: Color {
        if let tint {
            return tint.opacity(colorSchemeContrast == .increased ? 0.85 : 0.55)
        }
        return Color.primary.opacity(colorSchemeContrast == .increased ? 0.5 : 0.25)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if needsFallback {
            content
                .background {
                    shape
                        .fill(fallbackFill)
                        .allowsHitTesting(false)
                }
                .overlay {
                    shape
                        .stroke(fallbackStroke, lineWidth: colorSchemeContrast == .increased ? 2 : 1)
                        .allowsHitTesting(false)
                }
        } else {
            content
        }
    }
}

private struct PultContentSurface<S: Shape>: ViewModifier {
    var shape: S
    var tint: Color?
    var isProminent: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var fill: Color {
        if let tint {
            return tint.opacity(reduceTransparency ? 0.24 : 0.12)
        }
        if colorScheme == .dark {
            return Color.white.opacity(isProminent ? 0.14 : 0.09)
        }
        return Color.white.opacity(isProminent ? 0.80 : 0.62)
    }

    private var stroke: Color {
        if let tint {
            return tint.opacity(colorSchemeContrast == .increased ? 0.70 : 0.30)
        }
        return Color.primary.opacity(colorSchemeContrast == .increased ? 0.38 : 0.14)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(fill)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .stroke(stroke, lineWidth: colorSchemeContrast == .increased ? 1.5 : 1)
                    .allowsHitTesting(false)
            }
    }
}

/// Applies interactive Liquid Glass in an arbitrary shape with a press scale.
struct GlassShapeButtonStyle<S: Shape>: ButtonStyle {
    var shape: S

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        let scaledLabel = configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: configuration.isPressed)

        if reduceTransparency {
            scaledLabel
                .pultGlassFallback(in: shape, isProminent: true)
        } else {
            scaledLabel
                .background {
                    shape
                        .fill(PultDesign.surface)
                        .allowsHitTesting(false)
                }
                .glassEffect(.regular.interactive(), in: shape)
                .pultGlassFallback(in: shape, isProminent: true)
                .overlay {
                    shape
                        .stroke(PultDesign.hairline, lineWidth: 1)
                        .allowsHitTesting(false)
                }
        }
    }
}

/// A key zone that fires once on touch-down and auto-repeats while held.
/// Used for volume keys, where holding should keep adjusting. The repeater
/// is tied to the view's lifetime and the scene staying active, so a hold
/// interrupted by a call, backgrounding, or view removal cannot run away.
///
/// `sendSilently` is called for auto-repeat ticks so the haptic buzz from
/// sending every 180 ms is suppressed — the initial press via `send` still
/// produces haptic feedback. If `sendSilently` is nil it falls back to
/// `send` for both initial press and repeats.
struct HoldRepeatKeyZone: View {
    let key: RemoteKey
    var systemImage: String
    let send: (RemoteKey) -> Void
    var sendSilently: ((RemoteKey) -> Void)? = nil

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHolding = false
    @State private var repeater: Task<Void, Never>?

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(.rect)
            .scaleEffect(isHolding ? 0.86 : 1)
            .opacity(isHolding ? 0.6 : 1)
            .animation(reduceMotion ? nil : .snappy(duration: 0.16), value: isHolding)
            .gesture(holdGesture)
            .onDisappear(perform: stopHolding)
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active {
                    stopHolding()
                }
            }
            .accessibilityLabel(key.accessibilityLabel)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(holdAccessibilityHint)
            .accessibilityAction { send(key) }
            .accessibilityAction(named: "Press once") { send(key) }
    }

    private var holdAccessibilityHint: String {
        if differentiateWithoutColor {
            return "Double-tap to press once. Touch and hold to repeat."
        }
        return "Double-tap to press once. Touch and hold to repeat volume changes."
    }

    /// The closure used for auto-repeat ticks. Uses `sendSilently` when
    /// provided so haptic feedback is skipped on repeated sends.
    private var repeatSend: (RemoteKey) -> Void {
        sendSilently ?? send
    }

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard !isHolding else { return }
                isHolding = true
                send(key)                  // initial press — haptic fires here
                repeater = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(420))
                        while true {
                            try Task.checkCancellation()
                            repeatSend(key) // repeats — silent (no haptic)
                            try await Task.sleep(for: .milliseconds(180))
                        }
                    } catch {}
                }
            }
            .onEnded { _ in
                stopHolding()
            }
    }

    private func stopHolding() {
        isHolding = false
        repeater?.cancel()
        repeater = nil
    }
}

/// The quiet app-wide backdrop behind the remote surface.
struct RemoteBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    PultDesign.carbonTop,
                    PultDesign.carbonMid,
                    PultDesign.carbonBottom
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            if !reduceTransparency {
                PultSignalField()
                    .opacity(colorSchemeContrast == .increased ? 0.18 : 0.32)

                LinearGradient(
                    colors: [
                        PultDesign.accentDeep.opacity(0.28),
                        Color.clear,
                        PultDesign.utility.opacity(0.12)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [
                    Color.clear,
                    PultDesign.accent.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct PultSignalField: View {
    var body: some View {
        Canvas { context, size in
            let base = min(size.width, size.height)
            let center = CGPoint(x: size.width * 0.64, y: size.height * 0.24)
            var rings = Path()

            for index in 0..<6 {
                let diameter = base * (0.30 + CGFloat(index) * 0.18)
                let rect = CGRect(
                    x: center.x - diameter / 2,
                    y: center.y - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                rings.addEllipse(in: rect)
            }

            context.stroke(
                rings,
                with: .color(PultDesign.accent.opacity(0.10)),
                style: StrokeStyle(lineWidth: 1, dash: [2, 11], dashPhase: 3)
            )

            var scanlines = Path()
            let stride: CGFloat = 42
            var y: CGFloat = -size.height * 0.08
            while y < size.height * 1.10 {
                scanlines.move(to: CGPoint(x: -size.width * 0.08, y: y))
                scanlines.addLine(to: CGPoint(x: size.width * 1.08, y: y + size.width * 0.18))
                y += stride
            }

            context.stroke(
                scanlines,
                with: .color(PultDesign.utility.opacity(0.08)),
                style: StrokeStyle(lineWidth: 1)
            )
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
