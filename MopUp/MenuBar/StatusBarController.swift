import AppKit
import Observation
import SwiftUI

/// The menu bar item: the Mop Up icon with free disk space, and the shared
/// menu bar panel that drops down from it
@MainActor
final class StatusBarController {
    private let state: AppState
    private let statusItem: NSStatusItem
    private let panel: MenuBarPanelController

    init(state: AppState) {
        self.state = state
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let icon = NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: "Mop Up")
        icon?.isTemplate = true
        statusItem.button?.image = icon
        statusItem.button?.imagePosition = .imageLeading

        let panel = MenuBarPanelController(statusItem: statusItem)
        self.panel = panel
        panel.setContent {
            MenuBarPanel(close: { [weak panel] in panel?.close() }).environment(state)
        }
        panel.onOpen = { [state] in
            state.status.startWatching("menubar")
            state.refreshPermissions()
        }
        panel.onClose = { [state] in state.status.stopWatching("menubar") }

        state.status.startPolling()
        observe()
    }

    func remove() {
        panel.close()
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
                self?.panel.fitToContent()
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
}
