import SwiftUI

struct HistoryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.history
        Screen {
            ScreenHeader(title: "History", subtitle: "Every clean-up, uninstall and tune-up, newest first.") {
                RoundIconButton(symbol: "arrow.clockwise", size: 30, fill: AppColors.surface, foreground: AppColors.text, help: "Refresh") {
                    Task { await model.load() }
                }
            }

            if let error = model.error {
                MessageCard(title: "Couldn't read the history", message: error, mood: .sleepy, fill: AppColors.peach)
            } else if model.sessions.isEmpty {
                if model.isLoading {
                    WorkingCard(title: "Reading the history", detail: "", fill: AppColors.lilac)
                } else {
                    MessageCard(title: "Nothing yet", message: "Your clean-ups will show up here.", mood: .sleepy, fill: AppColors.lilac)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(model.sessions) { session in
                        HistoryRow(session: session)
                    }
                }
            }
        }
        .task { await model.load() }
    }
}

private struct HistoryRow: View {
    let session: CleanupHistory.Session

    var body: some View {
        HStack(spacing: 12) {
            SymbolTile(symbol: symbol, fill: tint, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.mono(12, weight: .semibold))
                    .foregroundStyle(AppColors.text)
                Text(when)
                    .font(.mono(10))
                    .foregroundStyle(AppColors.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let size = session.size, size != "0B" {
                    Text(ByteSize.tidy(size))
                        .font(.mono(11.5, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                }
                if let items = session.items, items > 0 {
                    Text("\(items) items")
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(radius: Radius.block)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch session.command {
        case "clean": return "Clean-up"
        case "uninstall": return "Uninstall"
        case "optimize": return "Tune-up"
        case "purge": return "Project purge"
        case "installer": return "Installer clean-up"
        default: return session.command.capitalized
        }
    }

    private var symbol: String {
        switch session.command {
        case "clean": return AppSection.clean.symbol
        case "uninstall": return AppSection.uninstall.symbol
        case "optimize": return AppSection.tuneUp.symbol
        default: return "sparkles"
        }
    }

    private var tint: Color {
        switch session.command {
        case "clean": return AppSection.clean.tint
        case "uninstall": return AppSection.uninstall.tint
        case "optimize": return AppSection.tuneUp.tint
        default: return AppColors.lilac
        }
    }

    private var when: String {
        guard let date = session.date else { return session.startedAt }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
