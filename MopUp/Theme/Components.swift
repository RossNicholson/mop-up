import SwiftUI

// MARK: - Buttons

extension EnvironmentValues {
    /// True inside a pastel card. Pastels look the same in light and dark
    /// mode, so buttons on them keep their light-mode ink colours.
    @Entry var onPastel = false
}

/// The dark pill with an icon in a coloured circle: the main action on a screen
struct PillButton: View {
    @Environment(\.onPastel) private var onPastel
    let title: String
    var symbol: String = "arrow.right"
    var circle: Color = AppColors.mint
    var destructive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(title)
                    .font(.display(17, relativeTo: .headline))
                    .textCase(.uppercase)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(AppColors.ink)
                    .frame(width: 24, height: 24)
                    .background(destructive ? AppColors.coral : circle, in: Circle())
            }
            .foregroundStyle(onPastel ? Color.white : AppColors.onSolid)
            .padding(.leading, 18)
            .padding(.trailing, 7)
            .padding(.vertical, 7)
            .background(onPastel ? AppColors.ink : AppColors.solid, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A quieter outlined pill for secondary actions ("Scan again", "Cancel")
struct GhostButton: View {
    @Environment(\.onPastel) private var onPastel
    let title: String
    var symbol: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                }
                Text(title)
                    .font(.mono(11, weight: .medium))
            }
            .foregroundStyle(onPastel ? AppColors.ink : AppColors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(onPastel ? Color.white.opacity(0.7) : AppColors.surface, in: Capsule())
            .overlay(Capsule().strokeBorder(onPastel ? Color.clear : AppColors.hairline))
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
    }
}

/// A filled circle with a symbol
struct RoundIconButton: View {
    let symbol: String
    var size: CGFloat = 26
    var fill: Color = AppColors.solid
    var foreground: Color = AppColors.onSolid
    var help: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help ?? "")
        .accessibilityLabel(help ?? symbol)
    }
}

/// Slight shrink while pressed, so plain buttons still feel tappable
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Labels

/// Small uppercase mono label in a capsule, e.g. "HOMEBREW" or "LOOK FIRST"
struct TagPill: View {
    let text: String
    var fill: Color = AppColors.butter
    var foreground: Color = AppColors.ink

    var body: some View {
        Text(text)
            .font(.mono(9, weight: .semibold))
            .textCase(.uppercase)
            .foregroundStyle(foreground)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(fill, in: Capsule())
    }
}

/// A rounded square with a symbol on a pastel
struct SymbolTile: View {
    let symbol: String
    let fill: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(AppColors.ink)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}

/// Large condensed title with a mono subtitle, at the top of every screen
struct ScreenHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.display(40, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.text)
                    .accessibilityAddTraits(.isHeader)
                Text(subtitle)
                    .font(.mono(11.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Mono caption above a group of cards
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.mono(10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(AppColors.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cards

extension View {
    /// White (or dark) rounded card
    func card(hovered: Bool = false, radius: CGFloat = 18) -> some View {
        background(hovered ? AppColors.surfaceHover : AppColors.surface,
                   in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    /// A pastel block; text on it is always ink
    func pastelCard(_ fill: Color, radius: CGFloat = 24) -> some View {
        foregroundStyle(AppColors.ink)
            .environment(\.onPastel, true)
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// A rounded bar showing how full something is
struct MeterBar: View {
    let fraction: Double
    var fill: Color = AppColors.ink
    var track: Color = AppColors.ink.opacity(0.12)
    var height: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fill)
                    .frame(width: max(height, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int((fraction * 100).rounded())) percent"))
    }
}

/// The pastel block shown while Mop Up works: mascot, title and the latest step
struct WorkingCard: View {
    let title: String
    let detail: String
    var fill: Color = AppColors.butter
    var onCancel: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 20) {
            Mascot(mood: .working, size: 92, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.display(28, relativeTo: .title))
                    .textCase(.uppercase)
                Text(detail.isEmpty ? " " : detail)
                    .font(.mono(11))
                    .opacity(0.75)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(AppColors.ink)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let onCancel {
                GhostButton(title: "Stop", symbol: "stop.fill", action: onCancel)
            }
        }
        .padding(24)
        .pastelCard(fill)
    }
}

/// A friendly message with the mascot, for empty and error states
struct MessageCard: View {
    let title: String
    let message: String
    var mood: Mascot.Mood = .happy
    var fill: Color = AppColors.mint

    var body: some View {
        HStack(spacing: 20) {
            Mascot(mood: mood, size: 84, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.display(26, relativeTo: .title))
                    .textCase(.uppercase)
                Text(message)
                    .font(.mono(11))
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(24)
        .pastelCard(fill)
    }
}

/// Page scaffold: ground colour, padding and a scroll view
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 32)
            .padding(.top, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.ground)
    }
}
