import SwiftUI

struct TuneUpView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.tuneUp
        Screen {
            ScreenHeader(title: "Tune Up", subtitle: "Routine maintenance: refresh caches and services, tidy app state and repair small problems.")

            switch model.phase {
            case .idle:
                IntroCard(
                    title: "Give it a tune-up",
                    message: "Mop Up refreshes Finder, Spotlight and network caches, checks preferences and login items, and fixes what it safely can. Some steps ask for your password.",
                    button: "Tune up my Mac",
                    symbol: "wrench.and.screwdriver.fill",
                    fill: AppColors.mint,
                    disabled: state.jobs.isBusy
                ) { model.tuneUp() }
                GhostButton(title: "Just check, don't change anything", symbol: "eye") { model.preview() }
            case let .working(preview):
                WorkingCard(title: preview ? "Checking" : "Tuning up", detail: model.step, fill: AppColors.mint) { model.cancel() }
            case let .preview(report):
                TuneUpSummary(report: report, preview: true)
                TuneUpChecks(report: report)
            case let .done(report):
                TuneUpSummary(report: report, preview: false)
                TuneUpChecks(report: report)
            case let .failed(message):
                MessageCard(title: "Something went wrong", message: message, mood: .sleepy, fill: AppColors.peach)
                GhostButton(title: "Back", symbol: "arrow.left") { model.reset() }
            }
        }
    }
}

private struct TuneUpSummary: View {
    @Environment(AppState.self) private var state
    let report: MoleReport
    let preview: Bool

    var body: some View {
        HStack(spacing: 24) {
            Mascot(mood: preview ? .happy : .proud, size: 110, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 6) {
                Text(preview ? "Here's the plan" : "All tuned up")
                    .font(.display(34, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                ForEach(report.summary.dropFirst().filter { !$0.hasPrefix("Run without") }, id: \.self) { line in
                    Text(line.replacingOccurrences(of: " | ", with: " · "))
                        .font(.mono(11))
                        .opacity(0.8)
                }
                HStack(spacing: 10) {
                    if preview {
                        PillButton(title: "Tune up now", symbol: "wrench.and.screwdriver.fill", circle: .white) {
                            state.tuneUp.tuneUp()
                        }
                        .disabled(state.jobs.isBusy)
                    } else {
                        PillButton(title: "Back to Home", symbol: "house.fill", circle: .white) {
                            state.tuneUp.reset()
                            state.section = .home
                        }
                    }
                    GhostButton(title: "Start over", symbol: "arrow.counterclockwise") { state.tuneUp.reset() }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .pastelCard(AppColors.mint, radius: 28)
    }
}

private struct TuneUpChecks: View {
    let report: MoleReport

    var body: some View {
        SectionLabel(text: "\(report.sections.count) checks")
            .padding(.top, 4)
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(report.sections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: Self.symbol(section))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.ink)
                            .frame(width: 22, height: 22)
                            .background(Self.tint(section), in: Circle())
                        Text(section.title)
                            .font(.display(16, relativeTo: .headline))
                            .textCase(.uppercase)
                            .foregroundStyle(AppColors.text)
                    }
                    ForEach(section.lines) { line in
                        Text([line.title, Friendly.detail(line.detail)].compactMap { $0 }.joined(separator: " · "))
                            .font(.mono(10))
                            .foregroundStyle(AppColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card(radius: 16)
            }
        }
    }

    static func symbol(_ section: ReportSection) -> String {
        if !section.warnings.isEmpty { return "exclamationmark" }
        if section.lines.contains(where: { $0.kind == .skipped }) { return "minus" }
        return "checkmark"
    }

    static func tint(_ section: ReportSection) -> Color {
        if !section.warnings.isEmpty { return AppColors.butter }
        if section.lines.contains(where: { $0.kind == .skipped }) { return AppColors.lilac }
        return AppColors.mint
    }
}
