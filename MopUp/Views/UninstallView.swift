import Combine
import SwiftUI

struct UninstallView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.uninstall
        VStack(spacing: 0) {
            Screen {
                ScreenHeader(title: "Uninstall", subtitle: "Remove apps along with their settings, caches and support files. They go to the Trash, so you can get them back, except Homebrew apps, which Homebrew deletes itself.") {
                    SearchField(text: $model.search)
                }

                switch model.phase {
                case .browsing, .planning, .confirm:
                    AppList()
                case .removing:
                    WorkingCard(title: "Uninstalling", detail: model.step, fill: AppColors.periwinkle)
                case let .done(summary, complete, homebrew):
                    UninstallDone(summary: summary, complete: complete, homebrew: homebrew)
                case let .failed(message):
                    MessageCard(title: "Couldn't uninstall", message: message, mood: .sleepy, fill: AppColors.peach)
                    GhostButton(title: "Back to apps", symbol: "arrow.left") { model.backToList() }
                }
            }
            if case .browsing = model.phase, !model.selection.isEmpty {
                SelectionBar()
            } else if case .planning = model.phase {
                SelectionBar()
            }
        }
        .background(AppColors.ground)
        .task { if model.apps.isEmpty { await model.load() } }
        .sheet(isPresented: Binding(
            get: { if case .confirm = model.phase { return true } else { return false } },
            set: { if !$0, case .confirm = model.phase { model.backToList() } }
        )) {
            if case let .confirm(plan, _) = model.phase {
                UninstallConfirmSheet(plan: plan)
            }
        }
    }
}

private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.secondaryText)
            TextField("Search apps", text: $text)
                .textFieldStyle(.plain)
                .font(.mono(11.5))
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AppColors.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 220)
        .background(AppColors.surface, in: Capsule(style: .circular))
        .overlay(Capsule(style: .circular).strokeBorder(focused ? AppColors.solid : AppColors.hairline))
        .contentShape(Capsule())
        .onTapGesture { focused = true }
    }
}

private struct AppList: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var model = state.uninstall
        if model.apps.isEmpty, model.isLoading {
            WorkingCard(title: "Finding your apps", detail: "Measuring each one", fill: AppColors.periwinkle)
        } else if let error = model.loadError, model.apps.isEmpty {
            MessageCard(title: "Couldn't list your apps", message: error, mood: .sleepy, fill: AppColors.peach)
            GhostButton(title: "Try again", symbol: "arrow.clockwise") { Task { await model.load() } }
        } else {
            HStack {
                SectionLabel(text: "\(model.visibleApps.count) apps")
                HStack(spacing: 2) {
                    ForEach(UninstallModel.Sort.allCases, id: \.self) { sort in
                        let on = model.sort == sort
                        Button {
                            model.sort = sort
                        } label: {
                            Text("By \(sort.rawValue.lowercased())")
                                .font(.mono(10.5, weight: on ? .semibold : .medium))
                                .foregroundStyle(on ? AppColors.onSolid : AppColors.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(on ? AppColors.solid : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
                .padding(2)
                .background(AppColors.surface, in: Capsule(style: .circular))
                RoundIconButton(symbol: "arrow.clockwise", size: 24, fill: AppColors.surface, foreground: AppColors.text, help: "Refresh") {
                    Task { await model.load() }
                }
                .disabled(!model.canChangeSelection)
            }
            LazyVStack(spacing: 6) {
                ForEach(model.visibleApps) { app in
                    AppRow(app: app, selected: model.selection.contains(app.id)) {
                        guard model.canChangeSelection else { return }
                        if model.selection.contains(app.id) {
                            model.selection.remove(app.id)
                        } else {
                            model.selection.insert(app.id)
                        }
                    }
                    // Fixed while Mop Up works out what would be removed
                    .disabled(!model.canChangeSelection)
                }
            }
            .padding(.bottom, 70)
        }
    }
}

private struct AppRow: View {
    let app: InstalledApp
    let selected: Bool
    let toggle: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? AppColors.toggle : AppColors.hairline)
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                    .resizable()
                    .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.mono(12, weight: .semibold))
                            .foregroundStyle(AppColors.text)
                        if app.isHomebrew {
                            TagPill(text: "Homebrew", fill: AppColors.butter)
                        }
                    }
                    Text(CleanPathFormatter.tilde(app.path))
                        .font(.mono(9.5))
                        .foregroundStyle(AppColors.secondaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(app.sizeBytes.map(ByteSize.format) ?? "")
                    .font(.mono(11, weight: .medium))
                    .foregroundStyle(AppColors.text)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .card(hovered: hovered, radius: Radius.block)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.block, style: .continuous)
                    .strokeBorder(selected ? AppColors.toggle : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.block))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\(app.name), \(app.sizeBytes.map(ByteSize.format) ?? "")")
    }
}

private struct SelectionBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let model = state.uninstall
        let apps = model.selectedApps
        let total = apps.compactMap(\.sizeBytes).reduce(0, +)
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(apps.count) selected")
                    .font(.display(20, relativeTo: .headline))
                    .textCase(.uppercase)
                Text(total > 0 ? "\(ByteSize.format(total)) plus leftovers" : "Plus their leftovers")
                    .font(.mono(10.5))
                    .opacity(0.75)
            }
            Spacer()
            if model.canChangeSelection {
                GhostButton(title: "Clear") { model.selection = [] }
            }
            if case .planning = model.phase {
                ProgressView().controlSize(.small)
                Text("Checking what to remove…").font(.mono(10.5))
            } else {
                PillButton(title: "Uninstall", symbol: "trash.fill", circle: AppColors.coral) { model.plan() }
                    .disabled(state.jobs.isBusy)
            }
        }
        .foregroundStyle(AppColors.ink)
        .environment(\.onPastel, true)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(AppColors.periwinkle)
    }
}

private struct UninstallConfirmSheet: View {
    @Environment(AppState.self) private var state
    let plan: UninstallPlan
    @State private var running: [NSRunningApplication] = []
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        let model = state.uninstall
        let homebrew = plan.apps.filter(\.isHomebrew).map(\.name)
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Mascot(mood: .happy, size: 56, disc: AppColors.periwinkle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(homebrew.isEmpty ? "Move to the Trash?" : "Remove these apps?")
                        .font(.display(28, relativeTo: .title))
                        .textCase(.uppercase)
                    Text(plan.summary.last ?? "These files will go to the Trash.")
                        .font(.mono(10.5))
                        .foregroundStyle(AppColors.secondaryText)
                }
            }

            if !running.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("\(running.compactMap(\.localizedName).formatted(.list(type: .and))) \(running.count == 1 ? "is" : "are") open. Quit first so nothing unsaved is lost.")
                        .font(.mono(10.5))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    PillButton(title: "Quit", symbol: "xmark", circle: AppColors.butter) {
                        running.forEach { $0.terminate() }
                    }
                }
                .padding(14)
                .pastelCard(AppColors.butter, radius: Radius.block)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.apps) { app in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(app.name)
                                    .font(.mono(12, weight: .semibold))
                                if app.isHomebrew {
                                    TagPill(text: "Homebrew", fill: AppColors.butter)
                                }
                                Spacer()
                                if let size = app.size {
                                    Text(size).font(.mono(11, weight: .medium))
                                }
                            }
                            ForEach(app.files) { file in
                                HStack {
                                    Text(CleanPathFormatter.tilde(file.path))
                                        .font(.mono(9.5))
                                        .foregroundStyle(AppColors.secondaryText)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    if let size = file.size {
                                        Text(size).font(.mono(9.5)).foregroundStyle(AppColors.secondaryText)
                                    }
                                }
                            }
                            ForEach(app.notes, id: \.self) { note in
                                Text(note)
                                    .font(.mono(9.5))
                                    .foregroundStyle(AppColors.secondaryText)
                            }
                        }
                        .padding(14)
                        .card(radius: Radius.row)
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 340)

            if !homebrew.isEmpty {
                // Homebrew deletes the app itself; only Mole's part goes to the Trash
                Text("Homebrew removes \(homebrew.formatted(.list(type: .and))) itself, so \(homebrew.count == 1 ? "it" : "they") won't be in the Trash. The leftovers listed above will be.")
                    .font(.mono(10.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pastelCard(AppColors.butter, radius: Radius.block)
            }

            HStack {
                Text("Some apps need your password to remove.")
                    .font(.mono(9.5))
                    .foregroundStyle(AppColors.secondaryText)
                Spacer()
                GhostButton(title: "Cancel") { model.backToList() }
                    .keyboardShortcut(.cancelAction)
                PillButton(title: homebrew.isEmpty ? "Move to Trash" : "Remove", symbol: "trash.fill", circle: AppColors.coral) { model.remove() }
                    .disabled(!running.isEmpty || state.jobs.isBusy)
                    .opacity(running.isEmpty ? 1 : 0.5)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(AppColors.ground)
        .onAppear { running = model.runningSelected() }
        .onReceive(ticker) { _ in running = model.runningSelected() }
    }
}

private struct UninstallDone: View {
    @Environment(AppState.self) private var state
    let summary: [String]
    let complete: Bool
    let homebrew: [String]

    var body: some View {
        HStack(spacing: 24) {
            Mascot(mood: complete ? .proud : .sleepy, size: 110, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 8) {
                Text(complete ? "Gone!" : "Partly done")
                    .font(.display(40, relativeTo: .largeTitle))
                    .textCase(.uppercase)
                ForEach(summary, id: \.self) { line in
                    Text(line)
                        .font(.mono(10.5))
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(homebrew.isEmpty
                     ? "Changed your mind? Everything is in the Trash until you empty it."
                     : "Homebrew deleted \(homebrew.formatted(.list(type: .and))) itself; reinstall \(homebrew.count == 1 ? "it" : "them") with Homebrew if you need \(homebrew.count == 1 ? "it" : "them") back. Everything else is in the Trash until you empty it.")
                    .fixedSize(horizontal: false, vertical: true)
                    .font(.mono(10.5))
                    .opacity(0.8)
                PillButton(title: "Back to apps", symbol: "arrow.left", circle: .white) {
                    state.uninstall.backToList()
                }
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(26)
        .pastelCard(complete ? AppColors.mint : AppColors.butter, radius: Radius.hero)
    }
}

enum CleanPathFormatter {
    static func tilde(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}
