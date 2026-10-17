import SwiftUI

@main
struct MopUpApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The main window and the menu bar item are managed by AppDelegate, so
        // Mop Up can keep running in the menu bar with its window closed.
        Settings { EmptyView() }
            .commands {
                CommandGroup(replacing: .appInfo) {
                    Button("About Mop Up") { appDelegate.show(.about) }
                }
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appSettings) {
                    Button("Settings…") { appDelegate.show(.about) }
                        .keyboardShortcut(",", modifiers: .command)
                }
                CommandMenu("Go") {
                    ForEach(Array(AppSection.allCases.enumerated()), id: \.element) { index, section in
                        Button(section.title) { appDelegate.show(section) }
                            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    }
                }
            }
    }
}

struct ContentView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(AppColors.ground)
        .ignoresSafeArea(.container, edges: .top)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.refreshPermissions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
    }

    @ViewBuilder private var detail: some View {
        switch state.section {
        case .home: HomeView()
        case .clean: CleanView()
        case .uninstall: UninstallView()
        case .tuneUp: TuneUpView()
        case .space: SpaceView()
        case .history: HistoryView()
        case .about: AboutView()
        }
    }
}

struct Sidebar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Mascot(size: 40, disc: AppColors.periwinkle)
                Text("Mop Up")
                    .font(.display(26, relativeTo: .title))
                    .textCase(.uppercase)
                    .foregroundStyle(AppColors.text)
            }
            .padding(.top, 46)
            .padding(.bottom, 18)
            .padding(.horizontal, 6)

            ForEach(AppSection.allCases.filter { $0 != .about }) { section in
                SidebarRow(section: section)
            }

            Spacer()

            if let job = state.jobs.running {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(job)
                        .font(.mono(10.5, weight: .medium))
                        .foregroundStyle(AppColors.secondaryText)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
            }
            SidebarRow(section: .about)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 214)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppColors.surface.opacity(0.55))
        .overlay(alignment: .trailing) {
            Rectangle().fill(AppColors.hairline).frame(width: 1)
        }
    }
}

private struct SidebarRow: View {
    @Environment(AppState.self) private var state
    let section: AppSection
    @State private var hovered = false

    var body: some View {
        let selected = state.section == section
        Button {
            state.section = section
        } label: {
            HStack(spacing: 10) {
                SymbolTile(symbol: section.symbol, fill: section.tint, size: 26)
                Text(section.title)
                    .font(.mono(12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(selected ? AppColors.onSolid : AppColors.text)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(selected ? AppColors.solid : (hovered ? AppColors.surfaceHover : .clear))
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Shown at the top of screens whose results improve with Full Disk Access
struct FullDiskAccessBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        if !state.hasFullDiskAccess {
            HStack(spacing: 14) {
                SymbolTile(symbol: "lock.open.fill", fill: .white.opacity(0.6), size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Let Mop Up see everything")
                        .font(.display(18, relativeTo: .headline))
                        .textCase(.uppercase)
                    Text("Give Mop Up Full Disk Access in System Settings so it can check every cache, find the files apps leave behind and empty the Trash. Turn it on, then come back here.")
                        .font(.mono(10.5))
                        .opacity(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                PillButton(title: "Open Settings", symbol: "arrow.up.right", circle: AppColors.butter) {
                    Permissions.openFullDiskAccessSettings()
                }
            }
            .padding(16)
            .pastelCard(AppColors.lilac, radius: Radius.window)
        }
    }
}
