import SwiftUI

struct CleanView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.clean
        Screen {
            ScreenHeader(title: "Clean Up", subtitle: "Caches, logs and leftovers your Mac doesn't need. Nothing is removed until you say so.")
            FullDiskAccessBanner()

            switch model.phase {
            case .idle:
                IntroCard(
                    title: "Find the junk",
                    message: "Mop Up looks through app caches, logs, browser leftovers, developer files and bits left behind by apps you've deleted, then shows you what it found.",
                    button: "Scan my Mac",
                    symbol: "magnifyingglass",
                    fill: AppColors.peach,
                    disabled: false
                ) { model.scan() }
            case .scanning:
                WorkingCard(title: "Looking for junk", detail: model.step, fill: AppColors.peach) { model.cancel() }
            case let .preview(report, files):
                CleanPreview(report: report, files: files)
            case .cleaning:
                WorkingCard(title: "Mopping up", detail: model.step, fill: AppColors.mint) { model.cancel() }
            case let .done(report):
                CleanDone(report: report)
            case let .failed(message):
                MessageCard(title: "Something went wrong", message: message, mood: .sleepy, fill: AppColors.peach)
                GhostButton(title: "Try again", symbol: "arrow.clockwise") { model.scan() }
            }
        }
    }
}

/// The big pastel card at the start of a job
struct IntroCard: View {
    let title: String
    let message: String
    let button: String
    let symbol: String
    let fill: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 24) {
            Mascot(mood: .happy, size: 120, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.display(32, relativeTo: .title))
                    .textCase(.uppercase)
                Text(message)
                    .font(.mono(11))
                    .opacity(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                PillButton(title: button, symbol: symbol, circle: .white, action: action)
                    .disabled(disabled)
                    .opacity(disabled ? 0.5 : 1)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .pastelCard(fill, radius: Radius.hero)
    }
}

private struct CleanPreview: View {
    @Environment(AppState.self) private var state
    let report: MoleReport
    let files: [String: [CleanFileList.Entry]]

    var body: some View {
        let toClean = report.sections.filter { !$0.actions.isEmpty }
        // Mole lists some big cleanable things again as "worth a look"; show them once
        let cleanedTitles = Set(toClean.flatMap(\.actions).map(\.title))
        let reviews = report.sections.flatMap(\.reviews).filter { !cleanedTitles.contains($0.title) }
        let warnings = report.sections.flatMap { section in section.warnings.map { (section.title, $0) } }
        let total = report.summaryValue("Potential space").map(ByteSize.tidy) ?? ByteSize.format(toClean.map(\.bytes).reduce(0, +))
        let itemCount = report.summaryValue("Items")

        if toClean.isEmpty {
            MessageCard(title: "Already spotless", message: "Mop Up didn't find anything worth cleaning right now.", mood: .proud)
            GhostButton(title: "Scan again", symbol: "arrow.clockwise") { state.clean.scan() }
        } else {
            HStack(spacing: 22) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready to clean")
                        .font(.mono(10, weight: .semibold))
                        .textCase(.uppercase)
                        .opacity(0.7)
                    Text(total)
                        .font(.display(56, relativeTo: .largeTitle))
                    Text([itemCount.map { "\($0) items" }, "in \(toClean.count) places"].compactMap { $0 }.joined(separator: " "))
                        .font(.mono(11))
                        .opacity(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .trailing, spacing: 10) {
                    PillButton(title: "Clean up \(total)", symbol: "sparkles", circle: AppColors.mint) {
                        state.clean.clean()
                    }
                    .disabled(state.jobs.isBusy)
                    GhostButton(title: "Scan again", symbol: "arrow.clockwise") { state.clean.scan() }
                }
            }
            .padding(24)
            .pastelCard(AppColors.peach, radius: Radius.hero)

            Text("Running apps keep their caches until they're closed. Apps rebuild caches as they need them, so cleaning is safe, though some may feel a little slower the first time you open them.")
                .font(.mono(10.5))
                .foregroundStyle(AppColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            SectionLabel(text: "What will be cleaned")
            ForEach(toClean) { section in
                CleanSectionCard(section: section, files: files[section.title] ?? [])
            }

            if !reviews.isEmpty {
                SectionLabel(text: "Worth a look — Mop Up won't touch these")
                    .padding(.top, 6)
                VStack(spacing: 0) {
                    ForEach(reviews) { line in
                        ReviewRow(line: line)
                        if line.id != reviews.last?.id { Divider().overlay(AppColors.hairline).padding(.leading, 16) }
                    }
                }
                .card(radius: Radius.window)
            }

            if !warnings.isEmpty {
                SectionLabel(text: "Skipped")
                    .padding(.top, 6)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(warnings, id: \.1.id) { section, line in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppColors.secondaryText)
                            Text([line.title, Friendly.detail(line.detail)].compactMap { $0 }.joined(separator: " — "))
                                .font(.mono(10.5))
                                .foregroundStyle(AppColors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(radius: Radius.window)
            }
        }
    }
}

private struct CleanSectionCard: View {
    let section: ReportSection
    let files: [CleanFileList.Entry]
    @State private var showFiles = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                SymbolTile(symbol: Self.symbol(for: section.title), fill: AppColors.pastel(for: section.title), size: 30)
                Text(section.title)
                    .font(.display(19, relativeTo: .headline))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.text)
                Spacer()
                if section.bytes > 0 {
                    Text(ByteSize.format(section.bytes))
                        .font(.mono(12, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                }
            }
            .padding(.bottom, 10)

            ForEach(section.actions) { line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.title)
                        .font(.mono(11, weight: .medium))
                        .foregroundStyle(AppColors.text)
                    if let detail = Friendly.detail(line.detail) {
                        Text(Self.withoutSize(detail))
                            .font(.mono(10))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                    Spacer()
                    if let bytes = line.bytes, bytes > 0 {
                        Text(ByteSize.format(bytes))
                            .font(.mono(10.5))
                            .foregroundStyle(AppColors.secondaryText)
                    }
                }
                .padding(.vertical, 3)
            }

            if !files.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { showFiles.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showFiles ? "chevron.down" : "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                        Text(showFiles ? "Hide files" : "Show \(files.count) \(files.count == 1 ? "file" : "files")")
                            .font(.mono(10, weight: .medium))
                    }
                    .foregroundStyle(AppColors.secondaryText)
                    .padding(.top, 8)
                }
                .buttonStyle(.plain)

                if showFiles {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(files) { file in
                            HStack {
                                Text(Self.tildePath(file.path))
                                    .font(.mono(9.5))
                                    .foregroundStyle(AppColors.secondaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                Spacer()
                                if let size = file.size {
                                    Text(size)
                                        .font(.mono(9.5))
                                        .foregroundStyle(AppColors.secondaryText)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(AppColors.ground, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    .padding(.top, 6)
                }
            }
        }
        .padding(16)
        .card(radius: Radius.window)
    }

    static func symbol(for title: String) -> String {
        let lower = title.lowercased()
        if lower.contains("browser") { return "globe" }
        if lower.contains("developer") || lower.contains("project") { return "hammer.fill" }
        if lower.contains("cloud") || lower.contains("office") { return "cloud.fill" }
        if lower.contains("leftover") { return "shippingbox.fill" }
        if lower.contains("system") { return "gearshape.fill" }
        if lower.contains("virtual") { return "square.stack.3d.up.fill" }
        if lower.contains("backup") || lower.contains("time machine") { return "clock.arrow.circlepath" }
        if lower.contains("large") { return "doc.fill" }
        if lower.contains("essential") || lower.contains("user") { return "person.fill" }
        if lower.contains("support") { return "folder.fill" }
        if lower.contains("update") { return "arrow.down.circle.fill" }
        return "sparkles"
    }

    /// The size is shown on the right, so drop it from "19 items, 707.2MB"
    static func withoutSize(_ detail: String) -> String {
        detail.replacing(/,?\s*\d+(?:\.\d+)?(?:B|KB|MB|GB|TB)\+?/, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,·"))
    }

    static func tildePath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct ReviewRow: View {
    let line: ReportLine

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(line.title)
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(AppColors.text)
                if let path = Friendly.path(in: line.detail) {
                    Text(CleanSectionCard.tildePath(path))
                        .font(.mono(9.5))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            if let bytes = line.bytes, bytes > 0 {
                Text(ByteSize.format(bytes))
                    .font(.mono(10.5, weight: .semibold))
                    .foregroundStyle(AppColors.text)
            }
            if let path = Friendly.path(in: line.detail) {
                RoundIconButton(symbol: "magnifyingglass", size: 24, fill: AppColors.butter, foreground: AppColors.ink, help: "Show in Finder") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

private struct CleanDone: View {
    @Environment(AppState.self) private var state
    let report: MoleReport

    var body: some View {
        let cancelled = report.headline?.localizedCaseInsensitiveContains("cancel") == true
            || report.headline?.localizedCaseInsensitiveContains("interrupt") == true
        let freed = report.summaryValue("Tracked cleanup")
        let free = report.summaryValue("Free space")

        HStack(spacing: 24) {
            Mascot(mood: cancelled ? .sleepy : .proud, size: 120, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 8) {
                Text(cancelled ? "Stopped" : "All clean!")
                    .font(.display(40, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                if let freed {
                    Text("Cleaned \(ByteSize.tidy(freed))")
                        .font(.display(22, relativeTo: .title2))
                        .textCase(.uppercase)
                }
                ForEach(report.summary.dropFirst().filter { !$0.hasPrefix("Tracked cleanup") }, id: \.self) { line in
                    Text(line)
                        .font(.mono(10.5))
                        .opacity(0.8)
                }
                if freed == nil, free == nil, report.summary.count <= 1 {
                    Text("Your Mac was already clean.")
                        .font(.mono(11))
                        .opacity(0.8)
                }
                HStack(spacing: 10) {
                    PillButton(title: "Back to Home", symbol: "house.fill", circle: .white) {
                        state.clean.reset()
                        state.section = .home
                    }
                    GhostButton(title: "Scan again", symbol: "arrow.clockwise") { state.clean.scan() }
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .pastelCard(AppColors.mint, radius: Radius.hero)
        .task { await state.status.refresh() }
    }
}
