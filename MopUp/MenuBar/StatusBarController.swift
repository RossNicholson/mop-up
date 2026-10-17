import AppKit
import Observation
import SwiftUI

/// The menu bar item: the Mop Up icon with free disk space, and a panel that
/// drops down from it (the same floating panel as ClawdBar)
@MainActor
final class StatusBarController: NSObject, NSWindowDelegate {
    private let state: AppState
    private let statusItem: NSStatusItem
    private var panel: NSPanel!
    private var eventMonitor: Any?

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: "Mop Up")
            icon?.isTemplate = true
            button.image = icon
            button.imagePosition = .imageLeading
            button.action = #selector(togglePanel)
            button.target = self
        }

        let content = MenuBarPanel { [weak self] in self?.closePanel() }
            .environment(state)
        let hosting = NSHostingView(rootView: content)
        hosting.autoresizingMask = [.width, .height]
        // The panel's title bar is hidden; don't leave a gap for it
        hosting.safeAreaRegions = []
        panel = makePanel(for: hosting)
        panel.contentView = hosting

        state.status.startPolling()
        observe()
    }

    func remove() {
        closePanel()
        state.status.stopPolling()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    // MARK: - Menu bar text

    /// Re-renders the title whenever the numbers or the running job change
    private func observe() {
        withObservationTracking {
            updateTitle()
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observe()
                self?.fitPanelToContent()
            }
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        if let job = state.jobs.running {
            button.attributedTitle = NSAttributedString(string: " \(job)…")
            button.toolTip = "Mop Up is \(job.lowercased())"
            return
        }
        guard let disk = state.status.status?.mainDisk else {
            button.title = ""
            return
        }
        // Space is tight up there: "19 GB" rather than "19.08 GB"
        let free = ByteCountFormatter.string(fromByteCount: disk.free, countStyle: .file)
            .replacingOccurrences(of: #"\.\d+ "#, with: " ", options: .regularExpression)
        let low = disk.fraction >= 0.9
        button.attributedTitle = NSAttributedString(
            string: " \(free)",
            attributes: low ? [.foregroundColor: NSColor.systemOrange] : [:]
        )
        button.toolTip = "\(free) free on your startup disk" + (low ? ". It's nearly full." : "")
    }

    // MARK: - Panel

    private func makePanel(for content: NSView) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: content.fittingSize),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }

    @objc private func togglePanel() {
        if panel.isVisible { closePanel() } else { openPanel() }
    }

    private func openPanel() {
        state.status.startWatching("menubar")
        state.refreshPermissions()
        fitPanelToContent()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        // Clicks on our own menu bar item arrive here too; leave those to togglePanel
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, !self.mouseIsOverStatusItem else { return }
                self.closePanel()
            }
        }
    }

    func closePanel() {
        guard panel.isVisible || eventMonitor != nil else { return }
        panel.orderOut(nil)
        state.status.stopWatching("menubar")
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    /// Resize the panel to its SwiftUI content, keeping it hanging from the menu bar
    private func fitPanelToContent() {
        guard let panel, let content = panel.contentView else { return }
        let size = content.fittingSize
        guard size != panel.frame.size, size.width > 0, size.height > 0 else { return }
        panel.setContentSize(size)
        if panel.isVisible { positionPanel() }
    }

    private func positionPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        let screenRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        guard let screen = buttonWindow.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        var x = screenRect.midX - panel.frame.width / 2
        x = min(max(x, screen.visibleFrame.minX + 4), screen.visibleFrame.maxX - panel.frame.width - 4)
        panel.setFrameOrigin(NSPoint(x: x, y: screenRect.minY - panel.frame.height))
    }

    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.panel.isVisible else { return }
            if NSApp.modalWindow != nil { return }
            // A click on the menu bar item is togglePanel's to handle
            if self.mouseIsOverStatusItem { return }
            self.closePanel()
        }
    }

    private var mouseIsOverStatusItem: Bool {
        guard let button = statusItem.button, let window = button.window else { return false }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return frame.contains(NSEvent.mouseLocation)
    }
}
