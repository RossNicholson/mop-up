import SwiftUI

struct AboutView: View {
    private let engine = MoleEngine.bundled
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Screen {
            HStack(spacing: 24) {
                Mascot(mood: .proud, size: 130, disc: .white.opacity(0.55))
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mop Up")
                        .font(.display(48, relativeTo: .largeTitle))
                        .textCase(.uppercase)
                    Text("Version \(version)")
                        .font(.mono(11, weight: .medium))
                        .opacity(0.75)
                    Text("Clean, uninstall and tune up your Mac. Free and open source.")
                        .font(.mono(11))
                        .opacity(0.8)
                    HStack(spacing: 14) {
                        MonoLink(title: "Website", destination: URL(string: "https://rossnicholson.dev")!)
                        MonoLink(title: "Source code", destination: URL(string: "https://github.com/RossNicholson/mop-up")!)
                    }
                    .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(26)
            .pastelCard(AppColors.periwinkle, radius: 28)

            SectionLabel(text: "Powered by Mole")
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text("Mop Up's cleaning engine is Mole \(engine.version), the open-source Mac cleaner by tw93. Mop Up is a friendly window on top of it: every scan, clean, uninstall and tune-up is done by Mole.")
                    .font(.mono(11))
                    .foregroundStyle(AppColors.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Mole is licensed under the GNU GPL v3. Mop Up includes an unmodified copy apart from one line: the title of its password dialog. The full source of the included version is published with every Mop Up release.")
                    .font(.mono(10.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    MonoLink(title: "Mole on GitHub", destination: URL(string: "https://github.com/tw93/Mole")!)
                    MonoLink(title: "Mole \(engine.version) source", destination: URL(string: "https://github.com/tw93/Mole/tree/V\(engine.version)")!)
                    MonoLink(title: "mole.fit", destination: URL(string: "https://mole.fit")!)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            SectionLabel(text: "Licence")
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 10) {
                Text("Mop Up is free software under the GNU General Public License v3. You can use, study, share and change it. It comes with no warranty.")
                    .font(.mono(10.5))
                    .foregroundStyle(AppColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 14) {
                    MonoLink(title: "GPL v3", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
                    Button("Show Mole's licence file") {
                        NSWorkspace.shared.selectFile(engine.root.appendingPathComponent("LICENSE").path, inFileViewerRootedAtPath: "")
                    }
                    .buttonStyle(.plain)
                    .font(.mono(10.5, weight: .medium))
                    .underline()
                    .foregroundStyle(AppColors.text)
                }
                Text("Fonts: Barlow Condensed and Geist Mono, SIL Open Font License.")
                    .font(.mono(10))
                    .foregroundStyle(AppColors.secondaryText)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }
}

/// Text link styled as a mono label
struct MonoLink: View {
    let title: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            Text(title)
                .font(.mono(10.5, weight: .medium))
                .foregroundStyle(AppColors.text)
                .underline()
        }
        .buttonStyle(.plain)
    }
}
