import SwiftUI

struct PultWelcomeEmptyState: View {
    let onAddTV: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {

                // ── Brand label ──────────────────────────────────────────
                HStack(spacing: 6) {
                    Rectangle()
                        .fill(PultDesign.accent.opacity(0.70))
                        .frame(width: 20, height: 1)
                    Text("PULT · GOOGLE TV REMOTE")
                        .font(PultTypography.label)
                        .foregroundStyle(PultDesign.accent)
                        .kerning(1.2)
                        .textCase(.uppercase)
                }
                .accessibilityLabel("Pult — Google TV Remote")

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 20 : 16)

                // ── Hero headline ────────────────────────────────────────
                Text("Your TV,\nfinally native.")
                    .font(PultTypography.display)
                    .foregroundStyle(PultDesign.warmInk)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 18 : 14)

                // ── Value proposition ────────────────────────────────────
                Text("Pair once, then drive the living room from the remote, keyboard, app launcher, Lock Screen, Control Center, Siri, and Shortcuts.")
                    .font(PultTypography.body)
                    .foregroundStyle(PultDesign.warmInk.opacity(0.50))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 36 : 28)

                // ── Hairline ─────────────────────────────────────────────
                Rectangle()
                    .fill(PultDesign.hairline)
                    .frame(height: 0.5)

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 28 : 22)

                // ── Capabilities (quiet list, no chips) ──────────────────
                PultEditorialCapabilities()

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 28 : 22)

                // ── Hairline ─────────────────────────────────────────────
                Rectangle()
                    .fill(PultDesign.hairline)
                    .frame(height: 0.5)

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 28 : 22)

                // ── Setup steps ──────────────────────────────────────────
                PultSetupSteps()

                Spacer().frame(height: dynamicTypeSize.isAccessibilitySize ? 36 : 28)

                // ── Primary CTA ──────────────────────────────────────────
                Button("Add TV", systemImage: "plus", action: onAddTV)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .tint(PultDesign.accent)
                    .accessibilityHint("Opens nearby TV scanning and manual address entry.")
            }
            .frame(maxWidth: 420, alignment: .leading)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
                max(length, dynamicTypeSize.isAccessibilitySize ? 680 : 560)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 36)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - Capabilities (restrained list, hairline-separated)

private struct PultEditorialCapabilities: View {
    private struct Capability {
        var systemImage: String
        var label: String
    }

    private let items: [Capability] = [
        Capability(systemImage: "dpad",                   label: "Full D-pad and media controls"),
        Capability(systemImage: "keyboard",               label: "Native keyboard and text entry"),
        Capability(systemImage: "lock.rectangle",         label: "Lock Screen persistent remote"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(PultDesign.hairline)
                        .frame(height: 0.5)
                }

                HStack(spacing: 14) {
                    Image(systemName: item.systemImage)
                        .font(.system(size: 14, weight: .light))
                        .foregroundStyle(PultDesign.accent)
                        .frame(width: 20, alignment: .center)
                        .accessibilityHidden(true)

                    Text(item.label)
                        .font(PultTypography.bodySmall)
                        .foregroundStyle(PultDesign.warmInk.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 13)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Setup steps (numbered, hairline-separated, no card)

private struct PultSetupSteps: View {
    private struct Step {
        var numeral: String
        var title: String
        var detail: String
    }

    private let steps: [Step] = [
        Step(numeral: "01", title: "Find",    detail: "Bonjour discovery when the TV is awake on the same network."),
        Step(numeral: "02", title: "Pair",    detail: "Enter the 6-character code shown on the TV screen."),
        Step(numeral: "03", title: "Control", detail: "Launch apps, type searches, and keep the remote alive on the Lock Screen."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(PultDesign.hairline)
                        .frame(height: 0.5)
                }

                HStack(alignment: .top, spacing: 16) {
                    Text(step.numeral)
                        .font(PultTypography.label)
                        .foregroundStyle(PultDesign.accent)
                        .kerning(0.5)
                        .frame(width: 24, alignment: .leading)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(PultTypography.subhead)
                            .foregroundStyle(PultDesign.warmInk)
                        Text(step.detail)
                            .font(PultTypography.bodySmall)
                            .foregroundStyle(PultDesign.warmInk.opacity(0.48))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 14)
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(step.title). \(step.detail)")
            }
        }
        .accessibilityElement(children: .contain)
    }
}
