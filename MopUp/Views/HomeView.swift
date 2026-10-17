import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let status = state.status.status
        Screen {
            ScreenHeader(title: "Your Mac", subtitle: subtitle(status))
            FullDiskAccessBanner()

            if let status {
                HStack(alignment: .top, spacing: 14) {
                    HealthCard(status: status)
                    DiskCard(disk: status.mainDisk, trash: status.trashSize)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    StatTile(label: "Memory", value: percent(status.memory?.usedPercent),
                             detail: memoryDetail(status), fraction: (status.memory?.usedPercent ?? 0) / 100)
                    StatTile(label: "Processor", value: percent(status.cpu?.usage),
                             detail: status.hardware?.cpuModel ?? "", fraction: (status.cpu?.usage ?? 0) / 100)
                    if let battery = status.batteries?.first, let level = battery.percent {
                        StatTile(label: "Battery", value: percent(level),
                                 detail: batteryDetail(battery), fraction: level / 100)
                    } else {
                        StatTile(label: "Running for", value: status.uptime ?? "–", detail: "since the last restart", fraction: nil)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } else if let error = state.status.error {
                MessageCard(title: "Couldn't check your Mac", message: error, mood: .sleepy, fill: AppColors.peach)
            } else {
                WorkingCard(title: "Checking your Mac", detail: "Disk, memory and health", fill: AppColors.lilac)
            }

            SectionLabel(text: "What would you like to do?")
                .padding(.top, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                JobCard(section: .clean, detail: "Clear out caches, logs and leftovers from apps you've deleted.")
                JobCard(section: .uninstall, detail: "Remove apps along with the files they leave behind.")
                JobCard(section: .tuneUp, detail: "Refresh caches and fix small things that slow your Mac down.")
                JobCard(section: .space, detail: "See which folders take up the most room.")
            }
        }
        .onAppear { state.status.startWatching() }
        .onDisappear { state.status.stopWatching() }
    }

    private func subtitle(_ status: SystemStatus?) -> String {
        guard let hw = status?.hardware else { return "A quick look at how things are" }
        return [hw.model, hw.cpuModel, hw.osVersion].compactMap { $0 }.joined(separator: " · ")
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return "\(Int(value.rounded()))%"
    }

    private func memoryDetail(_ status: SystemStatus) -> String {
        guard let used = status.memory?.used, let total = status.memory?.total else { return "" }
        return "\(ByteSize.formatMemory(used)) of \(ByteSize.formatMemory(total))"
    }

    private func batteryDetail(_ battery: SystemStatus.Battery) -> String {
        var parts: [String] = []
        if let status = battery.status, !status.isEmpty { parts.append(status.capitalized) }
        if let capacity = battery.capacity, capacity > 0 { parts.append("\(capacity)% health") }
        return parts.joined(separator: " · ")
    }
}

private struct HealthCard: View {
    let status: SystemStatus

    var body: some View {
        let score = status.healthScore ?? 0
        let (word, note) = Self.split(status.healthScoreMsg)
        HStack(alignment: .center, spacing: 18) {
            Mascot(mood: score >= 75 ? .happy : .sleepy, size: 86, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 2) {
                Text("Health")
                    .font(.mono(10, weight: .semibold))
                    .textCase(.uppercase)
                    .opacity(0.7)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(score)")
                        .font(.display(54, relativeTo: .largeTitle))
                    Text("/ 100")
                        .font(.mono(11, weight: .medium))
                        .opacity(0.6)
                }
                Text(word ?? "")
                    .font(.display(18, relativeTo: .headline))
                    .textCase(.uppercase)
                if let note {
                    Text(note)
                        .font(.mono(10.5))
                        .opacity(0.8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .pastelCard(score >= 75 ? AppColors.mint : (score >= 50 ? AppColors.butter : AppColors.peach))
        .accessibilityElement(children: .combine)
    }

    /// "Good: Disk Almost Full" → ("Good", "Disk almost full")
    static func split(_ message: String?) -> (String?, String?) {
        guard let message, !message.isEmpty else { return (nil, nil) }
        let parts = message.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        let note = parts.count > 1 ? parts[1].prefix(1).uppercased() + parts[1].dropFirst().lowercased() : nil
        return (parts[0], note)
    }
}

private struct DiskCard: View {
    @Environment(AppState.self) private var state
    let disk: SystemStatus.Disk?
    let trash: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Startup disk")
                .font(.mono(10, weight: .semibold))
                .textCase(.uppercase)
                .opacity(0.7)
            if let disk {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteSize.format(disk.free))
                        .font(.display(40, relativeTo: .largeTitle))
                    Text("free")
                        .font(.mono(11, weight: .medium))
                        .opacity(0.65)
                }
                MeterBar(fraction: disk.fraction, fill: disk.fraction > 0.9 ? AppColors.coral : AppColors.ink)
                Text("\(ByteSize.format(disk.used)) used of \(ByteSize.format(disk.total))")
                    .font(.mono(10.5))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
            HStack {
                if let trash, trash > 0 {
                    TagPill(text: "Trash \(ByteSize.format(trash))", fill: .white.opacity(0.7))
                }
                Spacer()
                Button {
                    state.section = .clean
                } label: {
                    HStack(spacing: 6) {
                        Text("Free up space")
                            .font(.mono(10.5, weight: .semibold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(AppColors.ink, in: Circle())
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .pastelCard(AppColors.butter)
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let detail: String
    let fraction: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.mono(10, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(AppColors.secondaryText)
            Text(value)
                .font(.display(30, relativeTo: .title))
                .foregroundStyle(AppColors.text)
            if let fraction {
                MeterBar(fraction: fraction, fill: AppColors.solid, track: AppColors.hairline, height: 6)
            }
            Text(detail)
                .font(.mono(10))
                .foregroundStyle(AppColors.secondaryText)
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .accessibilityElement(children: .combine)
    }
}

private struct JobCard: View {
    @Environment(AppState.self) private var state
    let section: AppSection
    let detail: String

    var body: some View {
        Button {
            state.section = section
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title)
                        .font(.display(22, relativeTo: .title2))
                        .textCase(.uppercase)
                    Text(detail)
                        .font(.mono(10.5))
                        .opacity(0.78)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(AppColors.ink, in: Circle())
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .pastelCard(section.tint, radius: 22)
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(PressableStyle())
    }
}
