import SwiftUI

struct SpaceView: View {
    @Environment(AppState.self) private var state
    @State private var pendingTrash: DiskScan.Entry?

    var body: some View {
        let model = state.space
        Screen {
            ScreenHeader(title: "Disk Space", subtitle: "See where your space has gone. Open a folder to look inside it.") {
                RoundIconButton(symbol: "arrow.clockwise", size: 30, fill: AppColors.surface, foreground: AppColors.text, help: "Scan again") {
                    Task { await model.rescan() }
                }
                .disabled(model.isLoading)
            }
            FullDiskAccessBanner()
            Breadcrumbs()

            if let error = model.error {
                MessageCard(title: "Couldn't read that", message: error, mood: .sleepy, fill: AppColors.peach)
            }

            if model.isLoading {
                WorkingCard(title: "Measuring", detail: CleanPathFormatter.tilde(model.currentPath ?? "Your whole Mac"), fill: AppColors.butter)
            } else if let scan = model.current {
                ScanList(scan: scan, pendingTrash: $pendingTrash)
            }
        }
        .task { await model.loadIfNeeded() }
        .confirmationDialog(
            "Move “\(pendingTrash?.name ?? "")” to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            presenting: pendingTrash
        ) { entry in
            Button("Move to Trash", role: .destructive) {
                Task { _ = await model.moveToTrash(entry.path) }
            }
        } message: { entry in
            Text("\(ByteSize.format(entry.size)) · \(CleanPathFormatter.tilde(entry.path))\nYou can get it back from the Trash until you empty it.")
        }
        .alert("Couldn't move that to the Trash", isPresented: Binding(
            get: { model.trashError != nil },
            set: { if !$0 { model.trashError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.trashError ?? "")
        }
    }
}

private struct Breadcrumbs: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let trail = state.space.trail
        if trail.count > 1 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(trail.enumerated()), id: \.offset) { index, path in
                        if index > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(AppColors.secondaryText)
                        }
                        let isLast = index == trail.count - 1
                        Button {
                            state.space.goBack(to: index)
                        } label: {
                            Text(path.map { ($0 as NSString).lastPathComponent } ?? "Your Mac")
                                .font(.mono(10.5, weight: isLast ? .semibold : .medium))
                                .foregroundStyle(isLast ? AppColors.onSolid : AppColors.text)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isLast ? AppColors.solid : AppColors.surface, in: Capsule())
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(isLast)
                    }
                }
            }
        }
    }
}

private struct ScanList: View {
    @Environment(AppState.self) private var state
    let scan: DiskScan
    @Binding var pendingTrash: DiskScan.Entry?

    var body: some View {
        let entries = scan.entries.filter { !$0.isUnavailable }.sorted { $0.size > $1.size }
        let biggest = max(entries.first?.size ?? 1, 1)
        let total = scan.totalSize ?? entries.map(\.size).reduce(0, +)

        HStack(alignment: .firstTextBaseline) {
            SectionLabel(text: scan.overview == true ? "The biggest places on your Mac" : "\(entries.count) items")
            Text(ByteSize.format(total))
                .font(.mono(11, weight: .semibold))
                .foregroundStyle(AppColors.text)
        }

        if entries.isEmpty {
            MessageCard(title: "Nothing here", message: "This folder is empty, or Mop Up isn't allowed to look inside it.", mood: .sleepy, fill: AppColors.butter)
        }

        VStack(spacing: 6) {
            ForEach(entries) { entry in
                SpaceRow(entry: entry, fraction: Double(entry.size) / Double(biggest),
                         canTrash: scan.overview != true) {
                    pendingTrash = entry
                }
            }
        }

        if let large = scan.largeFiles, !large.isEmpty {
            SectionLabel(text: "Big files")
                .padding(.top, 8)
            VStack(spacing: 6) {
                ForEach(large) { file in
                    SpaceRow(entry: .init(name: file.name, path: file.path, size: file.size, isDir: false,
                                          scanStatus: nil, insight: nil, cleanable: nil),
                             fraction: Double(file.size) / Double(max(large.first?.size ?? 1, 1)),
                             canTrash: true) {
                        pendingTrash = .init(name: file.name, path: file.path, size: file.size, isDir: false,
                                             scanStatus: nil, insight: nil, cleanable: nil)
                    }
                }
            }
        }
    }
}

private struct SpaceRow: View {
    @Environment(AppState.self) private var state
    let entry: DiskScan.Entry
    let fraction: Double
    let canTrash: Bool
    let trash: () -> Void
    @State private var hovered = false

    private var isApp: Bool { entry.path.hasSuffix(".app") }

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.path))
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.mono(11.5, weight: .semibold))
                        .foregroundStyle(AppColors.text)
                        .lineLimit(1)
                    if entry.cleanable == true {
                        TagPill(text: "Safe to clean", fill: AppColors.mint)
                    }
                    Spacer()
                    Text(ByteSize.format(entry.size))
                        .font(.mono(11, weight: .medium))
                        .foregroundStyle(AppColors.text)
                }
                MeterBar(fraction: fraction, fill: AppColors.pastel(for: entry.name), track: AppColors.hairline.opacity(0.5), height: 7)
            }
            HStack(spacing: 6) {
                RoundIconButton(symbol: "magnifyingglass", size: 24, fill: AppColors.ground, foreground: AppColors.text, help: "Show in Finder") {
                    NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "")
                }
                if isApp {
                    // Apps go through Uninstall, so their leftovers go too
                    RoundIconButton(symbol: "trash", size: 24, fill: AppColors.ground, foreground: AppColors.destructive, help: "Uninstall") {
                        state.uninstall.search = (entry.name as NSString).deletingPathExtension
                        state.section = .uninstall
                    }
                } else if canTrash {
                    RoundIconButton(symbol: "trash", size: 24, fill: AppColors.ground, foreground: AppColors.destructive, help: "Move to Trash", action: trash)
                }
            }
            .opacity(hovered ? 1 : 0.35)
            if entry.isDir && !isApp {
                RoundIconButton(symbol: "chevron.right", size: 24, help: "Open") {
                    Task { await state.space.open(entry.path) }
                }
            } else {
                Color.clear.frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(hovered: hovered, radius: 16)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) {
            if entry.isDir && !isApp { Task { await state.space.open(entry.path) } }
        }
    }
}
