import XCTest
import SwiftUI
@testable import Mop_Up

@MainActor
/// Renders every screen, the menu bar panel, the mascot and the social card
/// with demo data, for the website. Skipped unless SCREENSHOTS names an
/// output folder: `make screenshots`.
final class ScreenshotTests: XCTestCase {
    private var out: URL!

    override func setUpWithError() throws {
        guard let dir = ProcessInfo.processInfo.environment["SCREENSHOTS"], !dir.isEmpty else {
            throw XCTSkip("Set SCREENSHOTS to render screenshots")
        }
        out = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    }

    func testRenderScreens() throws {
        for (section, name) in [(AppSection.home, "home"), (.clean, "clean"), (.uninstall, "uninstall"),
                                (.tuneUp, "tuneup"), (.space, "space"), (.history, "history"), (.about, "settings")] {
            for dark in [false, true] {
                let state = AppState(engine: MoleEngine(root: URL(fileURLWithPath: "/nonexistent")))
                state.loadDemo()
                state.section = section
                let view = ContentView().environment(state).frame(width: 1040, height: 720)
                try render(view, size: NSSize(width: 1040, height: 720), dark: dark,
                           to: "\(name)\(dark ? "-dark" : "").png")
            }
        }
    }

    func testRenderPanel() throws {
        for dark in [false, true] {
            let state = AppState(engine: MoleEngine(root: URL(fileURLWithPath: "/nonexistent")))
            state.loadDemo()
            try Snapshot.panel(dark: dark, to: out.appendingPathComponent("panel\(dark ? "-dark" : "").png")) {
                MenuBarPanel(close: {}).environment(state)
            }
        }
    }

    func testRenderMascotAndOG() throws {
        try render(Mascot(mood: .proud, size: 280, disc: AppColors.periwinkle), size: NSSize(width: 280, height: 280), dark: false, to: "mascot.png", clear: true)
        try Snapshot.panel(to: out.appendingPathComponent("panel-about.png")) {
            AboutPopover(app: .mopUp) { Mascot(mood: .proud, size: 56, disc: AppColors.periwinkle) }
        }
        let og = HStack(spacing: 56) {
            Mascot(mood: .happy, size: 300, disc: .white.opacity(0.55))
            VStack(alignment: .leading, spacing: 14) {
                Text("Mop Up")
                    .font(.display(118))
                    .textCase(.uppercase)
                Text("Clean, uninstall and tune up your Mac.\nFree and open source.")
                    .font(.mono(25))
                    .opacity(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(AppColors.ink)
        .padding(.horizontal, 80)
        .frame(width: 1200, height: 630)
        .background(AppColors.periwinkle)
        try render(og, size: NSSize(width: 1200, height: 630), dark: false, to: "og-image.png", scale1: true)
    }

    private func render<V: View>(_ view: V, size: NSSize, dark: Bool, to file: String, clear: Bool = false, scale1: Bool = false) throws {
        try Snapshot.png(view, size: size, dark: dark, to: out.appendingPathComponent(file),
                         transparent: clear, exactPixels: scale1)
    }
}
