import SwiftUI

struct PultWelcomeEmptyState: View {
    let onAddTV: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    // ── Top breathing room ───────────────────────────────────
                    Spacer()
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 32 : 56)

                    // ── Title + subtitle ─────────────────────────────────────
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your TV, finally native.")
                            .font(PultTypography.display)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("A fast, native remote for Google TV.")
                            .font(PultTypography.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? 48 : 56)

                    // ── Feature rows ─────────────────────────────────────────
                    PultFeatureList()

                    Spacer()
                        .frame(minHeight: dynamicTypeSize.isAccessibilitySize ? 40 : 52)

                    // ── Primary CTA ──────────────────────────────────────────
                    Button(action: onAddTV) {
                        Text("Add TV")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(PultDesign.accent)
                    .accessibilityHint("Opens nearby TV scanning and manual address entry.")
                }
                .frame(maxWidth: 390)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(
                    minHeight: max(proxy.size.height, dynamicTypeSize.isAccessibilitySize ? 680 : 560)
                )
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Shared feature model

private struct OnboardingFeature {
    var systemImage: String
    var title: String
    var description: String
}

// MARK: - Feature list (Apple-style: symbol + bold title + description, no dividers)

private struct PultFeatureList: View {
    private let features: [OnboardingFeature] = [
        OnboardingFeature(
            systemImage: "dot.radiowaves.left.and.right",
            title: "Find your TV",
            description: "Pult discovers Google TV and Android TV devices on your Wi-Fi."
        ),
        OnboardingFeature(
            systemImage: "link",
            title: "Pair once",
            description: "Enter the 6-digit code shown on your TV. Pult remembers it."
        ),
        OnboardingFeature(
            systemImage: "av.remote",
            title: "Control everything",
            description: "Touchpad, keyboard, apps, volume — plus Lock Screen, Siri, and Control Center."
        ),
    ]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 36 : 28) {
            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                PultFeatureRow(feature: feature)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Single feature row

private struct PultFeatureRow: View {
    let feature: OnboardingFeature

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // At accessibility sizes the symbol moves above the text so it
                // stays legible and the text gets the full width.
                VStack(alignment: .leading, spacing: 12) {
                    symbolView
                    textStack
                }
            } else {
                // Apple onboarding pattern: symbol on the left, vertically
                // aligned with the title, text wrapping to the right.
                HStack(alignment: .top, spacing: 16) {
                    symbolView
                        .padding(.top, 2)
                    textStack
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.description)")
    }

    private var symbolView: some View {
        Image(systemName: feature.systemImage)
            .symbolRenderingMode(.hierarchical)
            .font(.system(size: 26, weight: .regular))
            .foregroundStyle(PultDesign.accent)
            .frame(width: 32, alignment: .center)
            .accessibilityHidden(true)
    }

    private var textStack: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(feature.title)
                .font(PultTypography.subhead)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text(feature.description)
                .font(PultTypography.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
