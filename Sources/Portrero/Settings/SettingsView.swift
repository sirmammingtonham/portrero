import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, browsers, linkRules, fileTypes, fileRules

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .browsers: "Browsers"
        case .linkRules: "Link Rules"
        case .fileTypes: "File Types"
        case .fileRules: "File Rules"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .browsers: "globe"
        case .linkRules: "link"
        case .fileTypes: "doc.fill"
        case .fileRules: "folder.fill"
        }
    }

    var color: Color {
        switch self {
        case .general: .gray
        case .browsers: .blue
        case .linkRules: .indigo
        case .fileTypes: .orange
        case .fileRules: .teal
        }
    }
}

struct SettingsView: View {
    @Bindable var navigation: SettingsNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $navigation.pane) {
                Section {
                    row(.general)
                }
                Section("Links") {
                    row(.browsers)
                    row(.linkRules)
                }
                Section("Files") {
                    row(.fileTypes)
                    row(.fileRules)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 200, max: 240)
        } detail: {
            detail
                .navigationTitle(navigation.pane.title)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // Always present, so the toolbar (and with it the full-height sidebar) never
                // comes and goes as panes with and without their own buttons are selected.
                .toolbar {
                    ToolbarItemGroup(placement: .navigation) {
                        Button(action: navigation.goBack) {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .disabled(navigation.backStack.isEmpty)
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Back")
                        Button(action: navigation.goForward) {
                            Label("Forward", systemImage: "chevron.right")
                        }
                        .disabled(navigation.forwardStack.isEmpty)
                        .keyboardShortcut("]", modifiers: .command)
                        .help("Forward")
                    }
                }
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private func row(_ pane: SettingsPane) -> some View {
        Label {
            Text(pane.title)
        } icon: {
            SettingsIcon(symbol: pane.symbol, color: pane.color)
        }
        .tag(pane)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.pane {
        case .general: GeneralPane()
        case .browsers: BrowsersPane()
        case .linkRules: RulesPane(kind: .link)
        case .fileTypes: FileTypesPane()
        case .fileRules: RulesPane(kind: .file)
        }
    }
}

/// White glyph on a coloured rounded square, like System Settings.
struct SettingsIcon: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous).fill(color.gradient))
    }
}
