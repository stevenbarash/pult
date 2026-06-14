import SwiftUI

// MARK: - Color helpers (scoped to this file, no clash with other mockups)

private func editorialColor(_ hex: UInt32, opacity: Double = 1) -> Color {
    let r = Double((hex >> 16) & 0xFF) / 255
    let g = Double((hex >> 8) & 0xFF) / 255
    let b = Double(hex & 0xFF) / 255
    return Color(red: r, green: g, blue: b, opacity: opacity)
}

// MARK: - Design tokens

private enum Editorial {
    /// Near-black, slightly warm
    static let background   = editorialColor(0x0A0A09)
    /// Off-white, slightly warm
    static let primary      = editorialColor(0xFAFAF7)
    /// Muted sage accent
    static let accent       = editorialColor(0x9DB39A)
    /// Hairline separator (white ~10%)
    static let hairline     = editorialColor(0xFAFAF7, opacity: 0.10)
    /// Subdued label text
    static let secondary    = editorialColor(0xFAFAF7, opacity: 0.42)
    /// Very dim tertiary
    static let tertiary     = editorialColor(0xFAFAF7, opacity: 0.22)
    /// Minimum tap target
    static let tapTarget: CGFloat = 44
    /// Consistent horizontal margin
    static let margin: CGFloat = 28
}

// MARK: - Root view

/// Self-contained visual mockup — "Editorial Calm" design direction.
/// No app model dependencies; static content only.
internal struct RemoteMockupEditorial: View {
    var body: some View {
        ZStack {
            Editorial.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 0)

                // ── Header ───────────────────────────────────────────────
                EditorialHeader()

                hairline()
                    .padding(.horizontal, Editorial.margin)
                    .padding(.top, 28)

                Spacer(minLength: 0)

                // ── D-Pad ────────────────────────────────────────────────
                EditorialDPad()

                Spacer(minLength: 0)

                hairline()
                    .padding(.horizontal, Editorial.margin)

                Spacer(minLength: 0)

                // ── Media row: back · home · play-pause ──────────────────
                EditorialMediaRow()

                Spacer(minLength: 0)

                hairline()
                    .padding(.horizontal, Editorial.margin)

                Spacer(minLength: 0)

                // ── Volume row ───────────────────────────────────────────
                EditorialVolumeRow()

                Spacer(minLength: 0)

                hairline()
                    .padding(.horizontal, Editorial.margin)

                Spacer(minLength: 0)

                // ── Utility row: keyboard · apps · search ────────────────
                EditorialUtilityRow()

                Spacer(minLength: 0)

                // ── Footer status ────────────────────────────────────────
                EditorialFooter()
                    .padding(.bottom, 10)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func hairline() -> some View {
        Rectangle()
            .fill(Editorial.hairline)
            .frame(height: 0.5)
    }
}

// MARK: - Header

private struct EditorialHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            // Accent pinstripe
            Rectangle()
                .fill(Editorial.accent.opacity(0.7))
                .frame(width: 28, height: 1)
                .padding(.bottom, 20)

            Text("Living Room TV")
                .font(.system(size: 38, weight: .light, design: .serif))
                .foregroundStyle(Editorial.primary)
                .tracking(0.4)
                .multilineTextAlignment(.center)

            Spacer().frame(height: 10)

            HStack(spacing: 6) {
                Circle()
                    .fill(Editorial.accent)
                    .frame(width: 5, height: 5)
                Text("Connected · Google TV")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Editorial.accent)
                    .kerning(0.8)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, Editorial.margin)
    }
}

// MARK: - D-Pad

private struct EditorialDPad: View {
    var body: some View {
        VStack(spacing: 0) {
            // Up
            GlyphButton(symbol: "chevron.up", label: nil)

            HStack(spacing: 0) {
                // Left
                GlyphButton(symbol: "chevron.left", label: nil)

                // Center OK
                Button(action: {}) {
                    ZStack {
                        Circle()
                            .strokeBorder(Editorial.tertiary, lineWidth: 0.5)
                            .frame(width: 52, height: 52)
                        Text("OK")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Editorial.secondary)
                            .kerning(1.2)
                            .textCase(.uppercase)
                    }
                }
                .frame(width: Editorial.tapTarget, height: Editorial.tapTarget)
                .padding(.horizontal, 16)

                // Right
                GlyphButton(symbol: "chevron.right", label: nil)
            }

            // Down
            GlyphButton(symbol: "chevron.down", label: nil)
        }
    }
}

// MARK: - Media row

private struct EditorialMediaRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlyphButton(symbol: "chevron.backward", label: "Back")
            Spacer(minLength: 0)
            GlyphButton(symbol: "house", label: "Home")
            Spacer(minLength: 0)
            GlyphButton(symbol: "playpause", label: "Play")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Editorial.margin)
    }
}

// MARK: - Volume row

private struct EditorialVolumeRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            GlyphButton(symbol: "speaker.slash", label: "Mute")

            Spacer(minLength: 0)

            // Volume minus
            GlyphButton(symbol: "minus", label: "Vol −")

            Spacer(minLength: 0)

            // Slim level indicator — 5 segments
            VolumePips()

            Spacer(minLength: 0)

            // Volume plus
            GlyphButton(symbol: "plus", label: "Vol +")

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Editorial.margin)
    }
}

private struct VolumePips: View {
    private let total = 5
    private let filled = 3

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i < filled ? Editorial.accent : Editorial.tertiary)
                    .frame(width: 3, height: i < filled ? 14 + CGFloat(i) * 3 : 10)
            }
        }
        .frame(width: Editorial.tapTarget, height: Editorial.tapTarget, alignment: .center)
    }
}

// MARK: - Utility row

private struct EditorialUtilityRow: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            GlyphButton(symbol: "keyboard", label: "Type")
            Spacer(minLength: 0)
            GlyphButton(symbol: "square.grid.2x2", label: "Apps")
            Spacer(minLength: 0)
            GlyphButton(symbol: "magnifyingglass", label: "Search")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Editorial.margin)
    }
}

// MARK: - Footer

private struct EditorialFooter: View {
    var body: some View {
        HStack(spacing: 0) {
            Text("PULT")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Editorial.tertiary)
                .kerning(2.5)

            Spacer()

            Text("Pult · 1.0")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(Editorial.tertiary)
                .kerning(0.5)
        }
        .padding(.horizontal, Editorial.margin)
        .padding(.top, 16)
    }
}

// MARK: - Shared glyph button

private struct GlyphButton: View {
    let symbol: String
    let label: String?

    var body: some View {
        Button(action: {}) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .thin))
                    .foregroundStyle(Editorial.primary.opacity(0.88))
                    .frame(width: 28, height: 28, alignment: .center)
                if let label {
                    Text(label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Editorial.secondary)
                        .kerning(0.5)
                        .textCase(.uppercase)
                }
            }
        }
        .frame(width: Editorial.tapTarget, height: Editorial.tapTarget)
    }
}

// MARK: - Preview

#Preview {
    RemoteMockupEditorial()
}
