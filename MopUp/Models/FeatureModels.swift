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
        startStream()
    }

    /// Whether the live stream is running
    var isStreaming: Bool { watcher != nil }

    /// How long to wait before restarting a stream that ended on its own
    @ObservationIgnored var restartDelay: Duration = .seconds(10)

    private func startStream() {
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
            guard !Task.isCancelled else { return }
            // Mole stopped streaming by itself (it crashed, say). Let the slow
            // poll take over, then try streaming again while anyone's watching.
            watcher = nil
            try? await Task.sleep(for: restartDelay)
            if !Task.isCancelled, watcher == nil, !watchers.isEmpty { startStream() }
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
        case preview(MoleReport, files: [String: [CleanFileList.Entry]], scannedAt: Date)
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

    /// A preview older than this is scanned again before cleaning: the clean
    /// runs afresh and would clean what's there now, not what was shown
    nonisolated static let previewLifetime: TimeInterval = 15 * 60

    nonisolated static func isStale(_ scannedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(scannedAt) > previewLifetime
    }

    func scan() {
        guard !isWorking else { return }
        phase = .scanning
        step = "Getting started"
        task = Task {
            do {
                let started = Date()
                let output = try await engine.run(["clean", "--dry-run"], onLine: progress)
                try Task.checkCancellation()
                let report = MoleReport.parse(output.lines)
                guard !report.sections.isEmpty else {
                    phase = .failed(Self.failure(output))
                    return
                }
                phase = .preview(report, files: CleanFileList.load(writtenSince: started), scannedAt: Date())
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func clean() {
        guard !isWorking else { return }
        // Only clean from a preview that finished and is still current
        if case let .preview(report, _, scannedAt) = phase {
            guard report.ending == .finished else { return }
            if Self.isStale(scannedAt) { scan(); return }
        }
        guard jobs.begin("Cleaning up") else { return }
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

    nonisolated static func failure(_ output: MoleEngine.Output) -> String {
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
        /// `finished` is false when it was stopped or didn't get to the end
        case done(MoleReport, finished: Bool)
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

    /// Mole prints its summary only when a run gets to the end: an
    /// interrupted one exits with 130 and no summary
    static func outcome(_ report: MoleReport, output: MoleEngine.Output, dryRun: Bool, cancelled: Bool) -> Phase {
        let finished = !cancelled && !report.summary.isEmpty && output.exitCode == 0
        if dryRun {
            if cancelled { return .idle }
            if finished && !report.sections.isEmpty { return .preview(report) }
            return .failed(report.sections.isEmpty ? CleanModel.failure(output)
                           : "The check didn't finish. \(CleanModel.failure(output))")
        }
        // A real tune-up may have changed things before it stopped: say what it did
        if report.sections.isEmpty && !finished {
            return cancelled ? .idle : .failed(CleanModel.failure(output))
        }
        return .done(report, finished: finished)
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
                phase = Self.outcome(report, output: output, dryRun: dryRun, cancelled: Task.isCancelled)
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
        /// The plan, and the apps it was made for: only these can be removed
        case confirm(UninstallPlan, apps: [InstalledApp])
        case removing
        /// Mole's summary; `complete` is false if some apps couldn't be removed.
        /// `homebrew` names the apps Homebrew removed, which aren't in the Trash.
        case done([String], complete: Bool, homebrew: [String])
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

    /// The list can only be changed while browsing, not while a plan is made or shown
    var canChangeSelection: Bool {
        if case .browsing = phase { return true }
        return false
    }

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
        let chosen = selectedApps
        guard !chosen.isEmpty, canChangeSelection else { return }
        let terms: [String]
        switch Self.terms(for: chosen, among: apps) {
        case let .success(found): terms = found
        case let .failure(problem):
            phase = .failed(problem.message)
            return
        }
        phase = .planning
        Task {
            do {
                // Mole asks "Proceed? [y/N]" then "Enter confirm" even in a dry run
                let output = try await engine.run(["uninstall", "--dry-run"] + terms, input: "y\n\n")
                let plan = UninstallPlan.parse(output.lines)
                if plan.apps.isEmpty {
                    phase = .failed(Self.failureMessage(output))
                } else if let problem = Self.mismatch(plan, chosen: chosen) {
                    phase = .failed(problem)
                } else {
                    phase = .confirm(plan, apps: chosen)
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Removes the apps in the plan the user confirmed, and their leftovers
    func remove() {
        guard case let .confirm(_, chosen) = phase, !chosen.isEmpty, jobs.begin("Uninstalling") else { return }
        phase = .removing
        step = chosen.map(\.name).formatted(.list(type: .and))
        Task {
            defer { jobs.end() }
            do {
                // Mole picks apps by name, so check against a fresh list that
                // the names still point at exactly these apps
                let fresh = try await engine.json([InstalledApp].self, ["uninstall", "--list"])
                let terms: [String]
                switch Self.terms(for: chosen, among: fresh) {
                case let .success(found): terms = found
                case let .failure(problem):
                    phase = .failed(problem.message + " Nothing was removed.")
                    await load()
                    return
                }
                let output = try await engine.run(["uninstall"] + terms, input: "y\n\n")
                phase = Self.outcome(output, removing: chosen)
                if case .done = phase { selection = [] }
                onDiskChanged?()
                await load()
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    struct MatchProblem: Error {
        let message: String
    }

    /// The name to give Mole for each app. Mole takes the first app whose name
    /// or .app folder name matches exactly, and falls back to any app whose
    /// name contains it, so each name must match this app and no other. The
    /// folder name comes first: it's what's on disk (a cask token like
    /// "google-chrome" matches nothing).
    nonisolated static func terms(for chosen: [InstalledApp], among all: [InstalledApp]) -> Result<[String], MatchProblem> {
        var terms: [String] = []
        for app in chosen {
            guard all.contains(where: { $0.path == app.path }) else {
                return .failure(MatchProblem(message: "\(app.name) isn't installed any more. Refresh the list and try again."))
            }
            let term = [app.folderName, app.name].first { candidate in
                let key = candidate.lowercased()
                // Mole would read a leading "-" as an option
                guard !candidate.isEmpty, !candidate.hasPrefix("-") else { return false }
                let matches = all.filter { $0.name.lowercased() == key || $0.folderName.lowercased() == key }
                return matches.map(\.path) == [app.path]
            }
            guard let term else {
                return .failure(MatchProblem(message: "Another app has the same name as \(app.name), so Mop Up can't be sure which one would be removed. Move the one you don't want to the Trash in Finder."))
            }
            terms.append(term)
        }
        return .success(terms)
    }

    /// Why Mole's plan isn't exactly the apps the user picked, if it isn't
    nonisolated static func mismatch(_ plan: UninstallPlan, chosen: [InstalledApp]) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expand = { (path: String) in path.hasPrefix("~/") ? home + path.dropFirst() : path }
        var unclaimed = plan.apps.map { Set($0.files.map { expand($0.path) }) }
        var missing: [String] = []
        for app in chosen {
            if let index = unclaimed.firstIndex(where: { $0.contains(app.path) }) {
                unclaimed.remove(at: index)
            } else {
                missing.append(app.name)
            }
        }
        guard !missing.isEmpty || !unclaimed.isEmpty else { return nil }
        let detail = missing.isEmpty
            ? "It also listed apps you didn't pick."
            : "It didn't include \(missing.formatted(.list(type: .and)))."
        return "Mop Up's cleaning engine planned something different from the apps you picked, so nothing will be removed. \(detail) Refresh the list and try again."
    }

    /// What a real uninstall did, from Mole's summary. Mole exits with 0 even
    /// when it removed nothing, so the summary is what counts.
    nonisolated static func outcome(_ output: MoleEngine.Output, removing chosen: [InstalledApp]) -> Phase {
        let summary = UninstallPlan.parse(output.lines).summary
        guard let headline = summary.first?.lowercased() else {
            return .failed(failureMessage(output))
        }
        if summary.contains(where: { $0.contains("No applications were uninstalled") }) {
            return .failed(summary.dropFirst().joined(separator: " "))
        }
        let complete = headline.contains("complete") && !headline.contains("incomplete")
        return .done(summary, complete: complete, homebrew: chosen.filter(\.isHomebrew).map(\.name))
    }

    /// Mole's reason for stopping before its summary, in plain words
    nonisolated static func failureMessage(_ output: MoleEngine.Output) -> String {
        let text = output.text
        if text.contains("No matching applications found") {
            return "Mop Up's cleaning engine couldn't find those apps any more, so nothing was removed. Refresh the list and try again."
        }
        if text.contains("Admin access denied") {
            return "Removing these needs your password, and macOS didn't get it. Nothing was removed."
        }
        if text.contains("Aborted.") {
            return "The uninstall stopped before removing anything."
        }
        return CleanModel.failure(output)
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
