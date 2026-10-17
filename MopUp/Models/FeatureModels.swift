import AppKit
import Observation

// MARK: - Home: live system status

@MainActor
@Observable
final class StatusModel {
    #if DEBUG
    func loadDemo(_ status: SystemStatus) {
        self.status = status
        isDemo = true
    }
    private var isDemo = false
    #endif

    private(set) var status: SystemStatus?
    private(set) var error: String?
    private let engine: MoleEngine
    private var watcher: Task<Void, Never>?
    private var poller: Task<Void, Never>?
    /// Who wants live numbers right now (Home, the menu bar panel)
    private var watchers: Set<String> = []

    init(engine: MoleEngine) { self.engine = engine }

    /// Streams fresh numbers every few seconds while anyone is watching
    func startWatching(_ who: String = "home") {
        #if DEBUG
        if isDemo { return }
        #endif
        watchers.insert(who)
        guard watcher == nil else { return }
        watcher = Task { [engine] in
            if status == nil {
                do {
                    status = try await engine.json(SystemStatus.self, ["status", "--json"]).withLiveStartupDisk()
                } catch {
                    self.error = error.localizedDescription
                }
            }
            for await snapshot in engine.watchStatus(every: 3) {
                var fresh = snapshot.withLiveStartupDisk()
                // Mole's first streamed snapshots can arrive before it has read
                // the hardware details; keep the ones we already have
                if (fresh.hardware?.model ?? "").isEmpty, let known = status?.hardware {
                    fresh.hardware = known
                }
                status = fresh
                error = nil
            }
        }
    }

    func stopWatching(_ who: String = "home") {
        watchers.remove(who)
        guard watchers.isEmpty else { return }
        watcher?.cancel()
        watcher = nil
    }

    /// A slow refresh for the menu bar's free-space figure, skipped while a
    /// live stream is already running
    func startPolling(every seconds: Int = 60) {
        #if DEBUG
        if isDemo { return }
        #endif
        guard poller == nil else { return }
        poller = Task {
            while !Task.isCancelled {
                if watcher == nil { await refresh() }
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stopPolling() {
        poller?.cancel()
        poller = nil
    }

    private(set) var isRefreshing = false

    /// One-off refresh (after a clean, say, or the refresh button)
    func refresh() async {
        #if DEBUG
        if isDemo { return }
        #endif
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        // The disk figure first: it's instant, and it's the one people watch
        if let status { self.status = status.withLiveStartupDisk() }
        if let fresh = try? await engine.json(SystemStatus.self, ["status", "--json"]) {
            status = fresh.withLiveStartupDisk()
        }
    }
}

// MARK: - Clean Up

@MainActor
@Observable
final class CleanModel {
    #if DEBUG
    func loadDemo(_ phase: Phase) { self.phase = phase }
    #endif

    enum Phase {
        case idle
        case scanning
        case preview(MoleReport, files: [String: [CleanFileList.Entry]])
        case cleaning
        case done(MoleReport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// The section Mole is working through right now
    private(set) var step = ""
    /// Lets the menu bar and Home catch up after a clean
    @ObservationIgnored var onDiskChanged: (() -> Void)?
    private let engine: MoleEngine
    private let jobs: JobGate
    private var task: Task<Void, Never>?

    init(engine: MoleEngine, jobs: JobGate) {
        self.engine = engine
        self.jobs = jobs
    }

    var isWorking: Bool {
        switch phase {
        case .scanning, .cleaning: return true
        default: return false
        }
    }

    func scan() {
        guard !isWorking else { return }
        phase = .scanning
        step = "Getting started"
        task = Task {
            do {
                let output = try await engine.run(["clean", "--dry-run"], onLine: progress)
                try Task.checkCancellation()
                let report = MoleReport.parse(output.lines)
                guard !report.sections.isEmpty else {
                    phase = .failed(Self.failure(output))
                    return
                }
                let listText = (try? String(contentsOf: CleanFileList.url, encoding: .utf8)) ?? ""
                phase = .preview(report, files: CleanFileList.parse(listText))
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func clean() {
        guard !isWorking, jobs.begin("Cleaning up") else { return }
        phase = .cleaning
        step = "Getting started"
        task = Task {
            defer { jobs.end() }
            do {
                let output = try await engine.run(["clean"], onLine: progress)
                let report = MoleReport.parse(output.lines)
                phase = report.summary.isEmpty ? .failed(Self.failure(output)) : .done(report)
                onDiskChanged?()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Stops a scan or clean. Mole finishes the item it's on and stops cleanly.
    func cancel() { task?.cancel() }

    func reset() { phase = .idle }

    private nonisolated var progress: @Sendable (String) -> Void {
        { line in
            guard line.hasPrefix("➤ ") else { return }
            let title = String(line.dropFirst(2))
            Task { @MainActor in self.step = title }
        }
    }

    static func failure(_ output: MoleEngine.Output) -> String {
        let tail = output.lines.suffix(3).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return tail.isEmpty ? "The cleaning engine stopped without a report (code \(output.exitCode))." : tail
    }
}

// MARK: - Tune Up

@MainActor
@Observable
final class TuneUpModel {
    #if DEBUG
    func loadDemo(_ phase: Phase) { self.phase = phase }
    #endif

    enum Phase {
        case idle
        case working(preview: Bool)
        case preview(MoleReport)
        case done(MoleReport)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var step = ""
    private let engine: MoleEngine
    private let jobs: JobGate
    private var task: Task<Void, Never>?

    init(engine: MoleEngine, jobs: JobGate) {
        self.engine = engine
        self.jobs = jobs
    }

    var isWorking: Bool {
        if case .working = phase { return true }
        return false
    }

    func preview() { run(dryRun: true) }
    func tuneUp() { run(dryRun: false) }
    func cancel() { task?.cancel() }
    func reset() { phase = .idle }

    private func run(dryRun: Bool) {
        guard !isWorking else { return }
        if !dryRun, !jobs.begin("Tuning up") { return }
        phase = .working(preview: dryRun)
        step = "Checking your Mac"
        task = Task {
            defer { if !dryRun { jobs.end() } }
            do {
                let output = try await engine.run(dryRun ? ["optimize", "--dry-run"] : ["optimize"]) { line in
                    guard line.hasPrefix("➤ ") else { return }
                    let title = String(line.dropFirst(2))
                    Task { @MainActor in self.step = title }
                }
                let report = MoleReport.parse(output.lines)
                if report.sections.isEmpty {
                    phase = .failed(CleanModel.failure(output))
                } else {
                    phase = dryRun ? .preview(report) : .done(report)
                }
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }
}

// MARK: - Uninstall

@MainActor
@Observable
final class UninstallModel {
    #if DEBUG
    func loadDemo(_ apps: [InstalledApp], selected: [String]) {
        self.apps = apps
        selection = Set(apps.filter { selected.contains($0.name) }.map(\.id))
    }
    #endif

    enum Phase {
        case browsing
        case planning
        case confirm(UninstallPlan)
        case removing
        case done([String])
        case failed(String)
    }

    enum Sort: String, CaseIterable { case size = "Size", name = "Name" }

    private(set) var apps: [InstalledApp] = []
    private(set) var isLoading = false
    private(set) var loadError: String?
    var selection: Set<InstalledApp.ID> = []
    var search = ""
    var sort: Sort = .size
    private(set) var phase: Phase = .browsing
    private(set) var step = ""
    /// Lets the menu bar and Home catch up after an uninstall
    @ObservationIgnored var onDiskChanged: (() -> Void)?

    private let engine: MoleEngine
    private let jobs: JobGate

    init(engine: MoleEngine, jobs: JobGate) {
        self.engine = engine
        self.jobs = jobs
    }

    var visibleApps: [InstalledApp] {
        let query = search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
        switch sort {
        case .size: return filtered.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
        case .name: return filtered.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    var selectedApps: [InstalledApp] { apps.filter { selection.contains($0.id) } }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await engine.json([InstalledApp].self, ["uninstall", "--list"])
            // Never offer to remove Mop Up itself
            let ownID = Bundle.main.bundleIdentifier
            apps = list.filter { $0.bundleID != ownID }
            selection = selection.filter { id in apps.contains { $0.id == id } }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Asks Mole what it would remove, without removing anything
    func plan() {
        let names = selectedApps.map(\.uninstallName)
        guard !names.isEmpty else { return }
        phase = .planning
        Task {
            do {
                // Mole asks "Proceed? [y/N]" then "Enter confirm" even in a dry run
                let output = try await engine.run(["uninstall", "--dry-run"] + names, input: "y\n\n")
                let plan = UninstallPlan.parse(output.lines)
                phase = plan.apps.isEmpty ? .failed(CleanModel.failure(output)) : .confirm(plan)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Moves the selected apps and their leftovers to the Trash
    func remove() {
        let chosen = selectedApps
        guard !chosen.isEmpty, jobs.begin("Uninstalling") else { return }
        phase = .removing
        step = chosen.map(\.name).formatted(.list(type: .and))
        Task {
            defer { jobs.end() }
            do {
                let output = try await engine.run(["uninstall"] + chosen.map(\.uninstallName), input: "y\n\n")
                let summary = UninstallPlan.parse(output.lines).summary
                selection = []
                phase = .done(summary.isEmpty ? ["Done."] : summary)
                onDiskChanged?()
                await load()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func backToList() { phase = .browsing }

    /// Selected apps that are open right now (they need quitting first)
    func runningSelected() -> [NSRunningApplication] {
        let paths = Set(selectedApps.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path })
        return NSWorkspace.shared.runningApplications.filter { app in
            guard let url = app.bundleURL?.standardizedFileURL.path else { return false }
            return paths.contains(url)
        }
    }
}

// MARK: - Disk Space

@MainActor
@Observable
final class SpaceModel {
    #if DEBUG
    func loadDemo(_ scan: DiskScan) { scans[Self.overviewKey] = scan }
    #endif

    /// Folders the user has opened, starting from the overview (nil)
    private(set) var trail: [String?] = [nil]
    private(set) var scans: [String: DiskScan] = [:]
    private(set) var loading: String?
    private(set) var error: String?
    /// Why the last move to Trash failed, shown as an alert
    var trashError: String?
    /// Lets the menu bar and Home catch up after a move to Trash
    @ObservationIgnored var onDiskChanged: (() -> Void)?
    private let engine: MoleEngine

    init(engine: MoleEngine) { self.engine = engine }

    private static let overviewKey = "#overview"

    var currentPath: String? { trail.last ?? nil }
    var current: DiskScan? { scans[currentPath ?? Self.overviewKey] }
    var isLoading: Bool { loading != nil }

    func loadIfNeeded() async {
        if current == nil, !isLoading { await scan(currentPath) }
    }

    func open(_ path: String) async {
        trail.append(path)
        if scans[path] == nil { await scan(path) }
    }

    func goBack(to index: Int) {
        guard index < trail.count else { return }
        trail.removeSubrange((index + 1)...)
    }

    func rescan() async {
        // Mole would otherwise reuse its cached results for recently changed folders
        MoleCache.clearDiskScans()
        scans[currentPath ?? Self.overviewKey] = nil
        await scan(currentPath)
    }

    private func scan(_ path: String?, retried: Bool = false) async {
        let key = path ?? Self.overviewKey
        loading = key
        error = nil
        defer { if loading == key { loading = nil } }
        do {
            let args = ["analyze", "--json"] + (path.map { [$0] } ?? [])
            var result = try await engine.json(DiskScan.self, args)
            // Mole's cache can still list things deleted in the last half hour
            // (in Finder, say). If it does, its totals are stale too: clear the
            // cache and measure once more. Either way, never show a ghost.
            let fm = FileManager.default
            let before = result.entries.count + (result.largeFiles?.count ?? 0)
            result.entries.removeAll { !fm.fileExists(atPath: $0.path) }
            result.largeFiles?.removeAll { !fm.fileExists(atPath: $0.path) }
            if !retried, result.entries.count + (result.largeFiles?.count ?? 0) < before {
                MoleCache.clearDiskScans()
                await scan(path, retried: true)
                return
            }
            scans[key] = result
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Moves a file or folder to the Trash (recoverable), then refreshes
    func moveToTrash(_ path: String) async -> Bool {
        // Already gone (moved in Finder, say): just take it off the list
        guard FileManager.default.fileExists(atPath: path) else {
            forget(path)
            return true
        }
        do {
            try await NSWorkspace.shared.recycle([URL(fileURLWithPath: path)])
        } catch {
            trashError = error.localizedDescription
            return false
        }
        // Don't rescan: Mole's scan cache trusts a folder for 30 minutes after
        // it changes, so a rescan would still list the item. Update the lists
        // here and clear Mole's cache so later scans measure afresh.
        forget(path)
        MoleCache.clearDiskScans()
        onDiskChanged?()
        return true
    }

    /// Removes a trashed item from every scan on screen and takes its size off
    /// the folders that contained it
    private func forget(_ path: String) {
        let removed = scans.values.flatMap { scan in
            scan.entries.filter { $0.path == path }.map(\.size) + (scan.largeFiles ?? []).filter { $0.path == path }.map(\.size)
        }.max() ?? 0
        let isInside = { (folder: String) in path.hasPrefix(folder.hasSuffix("/") ? folder : folder + "/") }

        for (key, var scan) in scans {
            scan.entries.removeAll { $0.path == path }
            scan.largeFiles?.removeAll { $0.path == path }
            for index in scan.entries.indices where isInside(scan.entries[index].path) {
                scan.entries[index].size = max(scan.entries[index].size - removed, 0)
            }
            if key == Self.overviewKey || isInside(key), let total = scan.totalSize {
                scan.totalSize = max(total - removed, 0)
            }
            scans[key] = scan
        }
    }
}

/// Mole's on-disk caches (~/.cache/mole)
enum MoleCache {
    /// Drops Mole's saved disk-scan results. They're rebuilt on the next scan;
    /// Mole clears them the same way after its own deletions.
    static func clearDiskScans() {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/mole/analyzer")
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - History

@MainActor
@Observable
final class HistoryModel {
    #if DEBUG
    func loadDemo(_ sessions: [CleanupHistory.Session]) {
        self.sessions = sessions
        isDemo = true
    }
    private var isDemo = false
    #endif

    private(set) var sessions: [CleanupHistory.Session] = []
    private(set) var isLoading = false
    private(set) var error: String?
    private let engine: MoleEngine

    init(engine: MoleEngine) { self.engine = engine }

    func load() async {
        #if DEBUG
        if isDemo { return }
        #endif
        isLoading = true
        defer { isLoading = false }
        do {
            let history = try await engine.json(CleanupHistory.self, ["history", "--json", "--limit", "100"])
            // Mole logs a session even when nothing happened; hide the empty ones
            sessions = history.sessions.filter { !$0.command.hasSuffix("dry-run") }.filter { ($0.items ?? 0) > 0 || ($0.actions?.removed ?? 0) > 0 || ($0.actions?.trashed ?? 0) > 0 }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
