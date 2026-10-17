import Foundation

/// Runs the copy of Mole (https://github.com/tw93/Mole) bundled inside the app.
///
/// Mop Up never talks to the user's own `mo` install: it runs the pinned copy
/// in Contents/Resources/mole, with no terminal attached. Without a terminal,
/// Mole skips its interactive menus, prints plain text and asks for an admin
/// password with a macOS dialog when a task needs one.
struct MoleEngine: Sendable {
    let root: URL

    static let bundled = MoleEngine(root: Bundle.main.resourceURL!.appendingPathComponent("mole"))

    var script: URL { root.appendingPathComponent("mole") }

    /// Version of the bundled Mole, from the VERSION file the vendor script writes
    var version: String {
        (try? String(contentsOf: root.appendingPathComponent("VERSION"), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
    }

    var isAvailable: Bool { FileManager.default.isReadableFile(atPath: script.path) }

    struct Output: Sendable {
        let exitCode: Int32
        let lines: [String]
        var text: String { lines.joined(separator: "\n") }
    }

    enum EngineError: LocalizedError {
        case missing
        case failed(code: Int32, message: String)
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .missing:
                return "Mop Up's cleaning engine is missing from the app. Try reinstalling Mop Up."
            case let .failed(code, message):
                return message.isEmpty ? "The cleaning engine stopped unexpectedly (code \(code))." : message
            case let .badOutput(detail):
                return "Mop Up couldn't read the engine's answer. \(detail)"
            }
        }
    }

    /// Runs `mole <arguments>`, calling `onLine` with each cleaned-up line as it
    /// arrives. `input` is written to stdin (for Mole's y/N prompts) and then
    /// closed. Cancelling the calling task stops Mole.
    func run(_ arguments: [String],
             input: String? = nil,
             onLine: (@Sendable (String) -> Void)? = nil) async throws -> Output {
        guard isAvailable else { throw EngineError.missing }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path] + arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.environment = Self.environment

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = stdout
        let stdin = Pipe()
        process.standardInput = input == nil ? FileHandle.nullDevice : stdin

        let box = ProcessBox(process)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Output, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try process.run()
                    } catch {
                        continuation.resume(throwing: error)
                        return
                    }
                    if let input {
                        stdin.fileHandleForWriting.write(Data(input.utf8))
                        try? stdin.fileHandleForWriting.close()
                    }

                    var splitter = LineSplitter()
                    var lines: [String] = []
                    let handle = stdout.fileHandleForReading
                    while true {
                        let data = handle.availableData
                        if data.isEmpty { break }
                        for line in splitter.feed(data) {
                            lines.append(line)
                            onLine?(line)
                        }
                    }
                    if let last = splitter.finish() {
                        lines.append(last)
                        onLine?(last)
                    }
                    process.waitUntilExit()
                    continuation.resume(returning: Output(exitCode: process.terminationStatus, lines: lines))
                }
            }
        } onCancel: {
            box.stop()
        }
    }

    /// Runs Mole and decodes its JSON output
    func json<T: Decodable>(_ type: T.Type, _ arguments: [String]) async throws -> T {
        let output = try await run(arguments)
        // Anything printed before the JSON (warnings) is skipped
        let text = output.text
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else {
            throw EngineError.failed(code: output.exitCode, message: text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        do {
            return try JSONDecoder().decode(T.self, from: Data(text[start...].utf8))
        } catch {
            throw EngineError.badOutput(error.localizedDescription)
        }
    }

    /// Streams `mole status --watch`: one decoded snapshot per interval, until cancelled
    func watchStatus(every seconds: Int) -> AsyncStream<SystemStatus> {
        AsyncStream { continuation in
            let task = Task {
                _ = try? await run(["status", "--watch", "--interval", "\(seconds)s"]) { line in
                    guard line.hasPrefix("{"),
                          let status = try? JSONDecoder().decode(SystemStatus.self, from: Data(line.utf8))
                    else { return }
                    continuation.yield(status)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// No terminal, no colours, and a PATH that finds Homebrew, npm and friends
    /// (GUI apps start with a bare PATH). The admin dialog is titled "Mop Up".
    static var environment: [String: String] {
        let inherited = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "SHELL"] {
            if let value = inherited[key] { env[key] = value }
        }
        env["HOME"] = env["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        env["MOLE_DIALOG_TITLE"] = "Mop Up"
        return env
    }
}

/// Lets the cancellation handler stop the process from another thread
private final class ProcessBox: @unchecked Sendable {
    private let process: Process
    private let lock = NSLock()

    init(_ process: Process) { self.process = process }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        // SIGINT first: Mole traps it, stops cleanly and still prints a summary
        if process.isRunning { process.interrupt() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) { [process] in
            if process.isRunning { process.terminate() }
        }
    }
}

/// Turns raw output bytes into display lines: splits on newlines, keeps only
/// the final state of lines redrawn with carriage returns (spinners), and
/// strips terminal escape codes.
struct LineSplitter {
    private var pending = Data()

    mutating func feed(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let lineData = pending[pending.startIndex..<newline]
            pending = Data(pending[pending.index(after: newline)...])
            if let line = Self.clean(lineData) { lines.append(line) }
        }
        return lines
    }

    mutating func finish() -> String? {
        defer { pending = Data() }
        return pending.isEmpty ? nil : Self.clean(pending)
    }

    static func clean(_ data: Data) -> String? {
        let raw = String(decoding: data, as: UTF8.self)
        // A spinner redraws with \r; what's after the last one is what's on screen
        let visible = raw.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
        return stripANSI(visible)
    }

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\u{1B}[@-_]", with: "", options: .regularExpression)
    }
}
