import SwiftUI

/// What drops down from the menu bar: a quick look at the Mac and shortcuts
/// into the main window
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    let close: () -> Void
    @State private var showingAbout = false

    var body: some View {
        let status = state.status.status
        VStack(alignment: .leading, spacing: 0) {
            PanelHeader(title: "Mop Up", subtitle: status?.hardware?.model ?? "Your Mac") {
                Mascot(mood: state.jobs.isBusy ? .working : .happy, size: PanelMetrics.mascot,
                       disc: AppColors.periwinkle)
            } actions: {
                HeaderRefreshButton(isRefreshing: state.status.isRefreshing) {
                    Task { await state.status.refresh() }
                }
                HeaderIconButton(symbol: "gearshape", help: "Settings") { open(.about) }
                HeaderIconButton(symbol: "info", help: "About & help") {
                    showingAbout.toggle()
                }
                .popover(isPresented: $showingAbout, arrowEdge: .bottom) {
                    AboutPopover(app: .mopUp) { Mascot(mood: .proud, size: 56, disc: AppColors.periwinkle) }
                }
            }

            VStack(spacing: 8) {
                if let job = state.jobs.running {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("\(job)…")
                            .font(.display(17, relativeTo: .headline))
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(12)
                    .pastelCard(AppColors.mint, radius: Radius.block)
                }

                if let disk = status?.mainDisk {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(ByteSize.format(disk.free))
                                .font(.display(30, relativeTo: .title))
                            Text("free")
                                .font(.mono(10.5, weight: .medium))
                                .opacity(0.65)
                            Spacer()
                            if let trash = status?.trashSize, trash > 0 {
                                TagPill(text: "Trash \(ByteSize.format(trash))", fill: .white.opacity(0.7))
                            }
                        }
                        MeterBar(fraction: disk.fraction, fill: disk.fraction > 0.9 ? AppColors.coral : AppColors.ink, height: 8)
                        Text("\(ByteSize.format(disk.used)) used of \(ByteSize.format(disk.total))")
                            .font(.mono(10))
                            .opacity(0.8)
                    }
                    .padding(14)
                    .pastelCard(AppColors.butter, radius: Radius.block)

                    HStack(spacing: 8) {
                        MiniStat(label: "Health", value: status?.healthScore.map(String.init) ?? "–")
                        MiniStat(label: "Memory", value: percent(status?.memory?.usedPercent))
                        MiniStat(label: "CPU", value: percent(status?.cpu?.usage))
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking your Mac…")
                            .font(.mono(10.5))
                            .foregroundStyle(AppColors.secondaryText)
                        Spacer()
                    }
                    .padding(14)
                    .card(radius: Radius.row)
                }

                PillButton(title: "Clean up my Mac", symbol: "sparkles", circle: AppColors.peach) {
                    close()
                    state.openWindow?(.clean)
                    if case .idle = state.clean.phase { state.clean.scan() }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    QuickButton(section: .uninstall) { open(.uninstall) }
                    QuickButton(section: .tuneUp) { open(.tuneUp) }
                    QuickButton(section: .space) { open(.space) }
                }
            }
            .padding(.horizontal, PanelMetrics.inset)
            .padding(.bottom, 12)

            // When the panel is made bigger, the extra room goes here
            Spacer(minLength: 0)
            PanelFooter {
                FooterButton(title: "Open Mop Up", symbol: "arrow.up.right") { open(nil) }
            }
        }
        .menuBarPanel()
    }

    private func open(_ section: AppSection?) {
        close()
        state.openWindow?(section)
    }

    private func percent(_ value: Double?) -> String {
        value.map { "\(Int($0.rounded()))%" } ?? "–"
    }
}

private struct MiniStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.mono(9, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.secondaryText)
            Text(value)
                .font(.display(20, relativeTo: .title3))
                .foregroundStyle(AppColors.text)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: Radius.small)
        .accessibilityElement(children: .combine)
    }
}

private struct QuickButton: View {
    let section: AppSection
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: section.symbol)
                    .font(.system(size: 12, weight: .semibold))
                Text(section.title)
                    .font(.mono(9.5, weight: .medium))
            }
            .foregroundStyle(AppColors.ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(section.tint, in: RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.small))
        }
        .buttonStyle(PressableStyle())
    }
}

/// Re-reads disk, memory and health straight away
struct RefreshButton: View {
    @Environment(AppState.self) private var state
    var size: CGFloat = 28

    var body: some View {
        if state.status.isRefreshing {
            ProgressView()
                .controlSize(.small)
                .frame(width: size, height: size)
        } else {
            RoundIconButton(symbol: "arrow.clockwise", size: size, fill: AppColors.surface,
                            foreground: AppColors.text, help: "Refresh") {
                Task { await state.status.refresh() }
            }
        }
    }
}
