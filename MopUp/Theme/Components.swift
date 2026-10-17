import SwiftUI

// Mop Up's own pieces. The shared buttons, labels and cards come from the
// HouseStyle package.

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
        .pastelCard(fill, radius: Radius.hero)
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
        .pastelCard(fill, radius: Radius.hero)
    }
}

