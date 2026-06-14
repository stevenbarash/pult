import SwiftUI

struct PultWelcomeEmptyState: View {
    let onAddTV: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 22 : 24) {
                PultRemoteLaunchPoster()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Your TV, finally native.")
                        .font(PultTypography.display)
                        .lineLimit(2)
                        .minimumScaleFactor(0.82)
                    Text("Pair once, then drive the living room from the remote, keyboard, app launcher, Lock Screen, Control Center, Siri, and Shortcuts.")
                        .font(PultTypography.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                        .minimumScaleFactor(0.86)
                }

                Button("Add TV", systemImage: "plus", action: onAddTV)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .accessibilityHint("Opens nearby TV scanning and manual address entry.")

                PultCapabilityStrip()

                VStack(alignment: .leading, spacing: 10) {
                    PultSetupStep(systemImage: "dot.radiowaves.left.and.right", title: "Find", detail: "Use Bonjour discovery when the TV is awake.")
                    PultSetupStep(systemImage: "link", title: "Pair", detail: "Enter the 6-character code shown on the TV.")
                    PultSetupStep(systemImage: "button.programmable", title: "Control", detail: "Launch apps, type searches, and keep the remote alive on the Lock Screen.")
                }
                .padding(16)
                .pultContentSurface(
                    in: RoundedRectangle(cornerRadius: 26, style: .continuous),
                    tint: .pultAccent,
                    isProminent: true
                )
            }
            .frame(maxWidth: 420, alignment: .leading)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
                max(length, dynamicTypeSize.isAccessibilitySize ? 680 : 560)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .scrollIndicators(.hidden)
    }
}

private struct PultRemoteLaunchPoster: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 34, style: .continuous)

        VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 18 : 16) {
            PultBrandLockup(subtitle: "Google TV remote", markSize: dynamicTypeSize.isAccessibilitySize ? 44 : 48)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 20) {
                    previewRemote
                    posterCopy
                }

                VStack(alignment: .leading, spacing: 14) {
                    previewRemote
                        .frame(maxWidth: .infinity, alignment: .center)
                    posterCopy
                }
            }
        }
        .padding(dynamicTypeSize.isAccessibilitySize ? 16 : 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape
                .fill(
                    LinearGradient(
                        colors: [
                            PultDesign.surfaceStrong,
                            PultDesign.surface.opacity(0.52),
                            Color.black.opacity(0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(alignment: .topTrailing) {
                    PultSignalBurst()
                        .frame(width: 178, height: 178)
                        .padding(.top, -36)
                        .padding(.trailing, -30)
                }
                .overlay {
                    shape.stroke(PultDesign.hairlineStrong, lineWidth: 1)
                }
        }
        .clipShape(shape)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Pult Google TV remote with Lock Screen, keyboard, and app launch controls.")
    }

    private var previewRemote: some View {
        VStack(spacing: 8) {
            Circle()
                .fill(PultDesign.danger.opacity(0.92))
                .frame(width: 14, height: 14)
                .overlay {
                    Image(systemName: "power")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(PultDesign.warmInk)
                }

            ZStack {
                Circle()
                    .stroke(PultDesign.accent.opacity(0.64), lineWidth: 7)
                Circle()
                    .fill(PultDesign.surfaceStrong)
                    .frame(width: 34, height: 34)
                ForEach(0..<4, id: \.self) { index in
                    Image(systemName: "chevron.up")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(PultDesign.accent)
                        .offset(y: -36)
                        .rotationEffect(.degrees(Double(index) * 90))
                }
            }
            .frame(width: 90, height: 90)

            HStack(spacing: 8) {
                ForEach(["arrow.uturn.backward", "house.fill", "playpause.fill"], id: \.self) { systemImage in
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(systemImage == "playpause.fill" ? PultDesign.accent : PultDesign.warmInk.opacity(0.84))
                        .frame(width: 27, height: 27)
                        .background(PultDesign.surfaceRaised, in: Circle())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .background {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.84),
                            PultDesign.carbonMid.opacity(0.94),
                            Color.black.opacity(0.92)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(PultDesign.accent.opacity(0.30), lineWidth: 1)
                }
        }
        .shadow(color: PultDesign.accent.opacity(0.24), radius: 28, y: 16)
        .frame(width: 126)
        .accessibilityHidden(true)
    }

    private var posterCopy: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    PultStatusChip(title: "Keyboard", systemImage: "keyboard", tint: .pultAccent)
                    PultStatusChip(title: "Lock Screen", systemImage: "lock.fill", tint: PultDesign.utility)
                    PultStatusChip(title: "Shortcuts", systemImage: "sparkles", tint: PultDesign.warning)
                    PultStatusChip(title: "Control Center", systemImage: "slider.horizontal.3", tint: PultDesign.utility)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        PultStatusChip(title: "Keyboard", systemImage: "keyboard", tint: .pultAccent)
                        PultStatusChip(title: "Lock Screen", systemImage: "lock.fill", tint: PultDesign.utility)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PultStatusChip(title: "Keyboard", systemImage: "keyboard", tint: .pultAccent)
                        PultStatusChip(title: "Lock Screen", systemImage: "lock.fill", tint: PultDesign.utility)
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        PultStatusChip(title: "Shortcuts", systemImage: "sparkles", tint: PultDesign.warning)
                        PultStatusChip(title: "Control Center", systemImage: "slider.horizontal.3", tint: PultDesign.utility)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        PultStatusChip(title: "Shortcuts", systemImage: "sparkles", tint: PultDesign.warning)
                        PultStatusChip(title: "Control Center", systemImage: "slider.horizontal.3", tint: PultDesign.utility)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PultSignalBurst: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.58, y: size.height * 0.42)
            var path = Path()

            for index in 0..<5 {
                let diameter = CGFloat(42 + index * 32)
                path.addEllipse(
                    in: CGRect(
                        x: center.x - diameter / 2,
                        y: center.y - diameter / 2,
                        width: diameter,
                        height: diameter
                    )
                )
            }

            context.stroke(
                path,
                with: .color(PultDesign.accent.opacity(0.16)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 10])
            )
        }
        .blendMode(.screen)
        .accessibilityHidden(true)
    }
}

private struct PultCapabilityStrip: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                capabilities
            }

            VStack(alignment: .leading, spacing: 8) {
                capabilities
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var capabilities: some View {
        PultStatusChip(title: "D-pad", systemImage: "dpad", tint: .pultAccent)
        PultStatusChip(title: "Text Entry", systemImage: "text.cursor", tint: PultDesign.utility)
        PultStatusChip(title: "Live Activity", systemImage: "rectangle.on.rectangle", tint: PultDesign.warning)
    }
}

private struct PultSetupStep: View {
    var systemImage: String
    var title: String
    var detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.pultAccent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PultTypography.subhead)
                Text(detail)
                    .font(PultTypography.bodySmall)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
            .accessibilityElement(children: .combine)
    }
}
