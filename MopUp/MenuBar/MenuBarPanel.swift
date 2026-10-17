import SwiftUI

/// What drops down from the menu bar: a quick look at the Mac and shortcuts
/// into the main window
struct MenuBarPanel: View {
    @Environment(AppState.self) private var state
    let close: () -> Void

    var body: some View {
        let status = state.status.status
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Mascot(mood: state.jobs.isBusy ? .working : .happy, size: 42, disc: AppColors.periwinkle)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Mop Up")
                        .font(.display(28, relativeTo: .largeTitle))
                        .textCase(.uppercase)
                        .foregroundStyle(AppColors.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(status?.hardware?.model ?? "Your Mac")
                        .font(.mono(10))
                        .foregroundStyle(AppColors.secondaryText)
                }
                Spacer()
            }
            .padding(14)

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
                    .pastelCard(AppColors.mint, radius: 16)
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
                    .pastelCard(AppColors.butter, radius: 18)

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
                    .card(radius: 16)
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
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            Divider().overlay(AppColors.hairline)
            HStack {
                Button("Open Mop Up") { open(nil) }
                Spacer()
                Button("Settings") { open(.about) }
                Text("·").foregroundStyle(AppColors.secondaryText)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.mono(10.5, weight: .medium))
            .foregroundStyle(AppColors.text)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .background(AppColors.ground)
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
        .card(radius: 12)
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
            .background(section.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PressableStyle())
    }
}
