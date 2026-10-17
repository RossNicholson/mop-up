import AppKit
import ServiceManagement
import SwiftUI

/// Owns the main window and the menu bar item. With the menu bar item on,
/// closing the window keeps Mop Up running there (no Dock icon); with it off,
/// closing the window quits, like a normal app.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = AppState()
    private var window: NSWindow?
    private var statusBar: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.openWindow = { [weak self] section in self?.show(section) }
        state.settings.onChange = { [weak self] in self?.applySettings() }

        // Don't open windows or start polling when hosting unit tests
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        #if DEBUG
        // `-demo YES`: sample data for screenshots, no engine calls
        if UserDefaults.standard.bool(forKey: "demo") { state.loadDemo() }
        #endif
        applySettings()
        Task { await state.updater.checkSilent() }
        // Opened at login: start quietly in the menu bar
        if state.settings.showInMenuBar, Self.launchedAtLogin {
            NSApp.setActivationPolicy(.accessory)
        } else {
            show(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { show(nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !state.settings.showInMenuBar
    }

    // MARK: - Main window

    /// Brings the window forward, optionally on a given screen
    func show(_ section: AppSection?) {
        if let section { state.section = section }
        NSApp.setActivationPolicy(.regular)
        let window = self.window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let content = ContentView()
            .environment(state)
            .frame(minWidth: 860, minHeight: 600)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Mop Up"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.contentMinSize = NSSize(width: 860, height: 600)
        window.delegate = self
        if !window.setFrameUsingName("MainWindow") { window.center() }
        window.setFrameAutosaveName("MainWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // Back to a menu bar app: no Dock icon while the window is closed
        if state.settings.showInMenuBar {
            DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
        }
    }

    // MARK: - Settings

    private func applySettings() {
        if state.settings.showInMenuBar {
            if statusBar == nil { statusBar = StatusBarController(state: state) }
        } else {
            statusBar?.remove()
            statusBar = nil
            // Without the menu bar item there must be a way back: keep the Dock icon
            if window?.isVisible != true { show(nil) }
        }
    }

    /// Whether macOS opened us as a login item. The launch event says so for
    /// older login items; for SMAppService ones the best signal is that the
    /// setting is on and the Mac has only just started up.
    private static var launchedAtLogin: Bool {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventID == kAEOpenApplication,
           event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            return true
        }
        return AppSettings.openAtLogin && ProcessInfo.processInfo.systemUptime < 180
    }
}

/// User settings, kept in UserDefaults
@MainActor
@Observable
final class AppSettings {
    var onChange: (() -> Void)?

    var showInMenuBar: Bool = UserDefaults.standard.object(forKey: "showInMenuBar") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showInMenuBar, forKey: "showInMenuBar")
            onChange?()
        }
    }

    /// Set by SMAppService; read back from it so it matches System Settings
    private(set) var openAtLoginEnabled = AppSettings.openAtLogin
    private(set) var loginError: String?

    nonisolated static var openAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "macOS didn't allow that: \(error.localizedDescription)"
        }
        openAtLoginEnabled = Self.openAtLogin
    }
}
