import SwiftUI

struct BrowsersPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let browsers = model.orderedBrowsers
        let visibleIDs = model.pickerBrowsers.map(\.id)

        Form {
            Section {
                if browsers.isEmpty {
                    Text("No browsers found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(browsers) { browser in
                    BrowserRow(
                        browser: browser,
                        shortcut: visibleIDs.firstIndex(of: browser.id).flatMap { $0 < 9 ? $0 + 1 : nil },
                        isVisible: Binding(
                            get: { !model.isHidden(browser) },
                            set: { model.setHidden(!$0, browser) }
                        )
                    )
                }
                .onMove(perform: model.moveBrowsers)
            } header: {
                Text("Shown in the Picker")
            } footer: {
                Text("Drag to reorder — the first nine get number shortcuts. Profiles from Chrome, Edge, Brave, Vivaldi and Firefox are picked up automatically.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button {
                model.refresh()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Look for new browsers and profiles")
        }
    }
}

private struct BrowserRow: View {
    let browser: Browser
    let shortcut: Int?
    @Binding var isVisible: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            BrowserIcon(browser: browser, size: 28)
                .opacity(isVisible ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                Text(browser.title)
                let note = browser.isWebBrowser ? nil : "Opens links, but isn’t a web browser"
                if let detail = [browser.subtitle, browser.profileDetail, note].compactMap({ $0 }).nonEmptyJoined(" · ") {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(isVisible ? .primary : .secondary)
            Spacer()
            if let shortcut, isVisible {
                Keycap(text: "\(shortcut)")
            }
            Toggle("Show in picker", isOn: $isVisible)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }
}

extension Array where Element == String {
    func nonEmptyJoined(_ separator: String) -> String? {
        isEmpty ? nil : joined(separator: separator)
    }
}
