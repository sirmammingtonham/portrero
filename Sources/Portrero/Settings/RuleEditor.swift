import AppKit
import PortreroCore
import SwiftUI
import UniformTypeIdentifiers

struct RuleEditor: View {
    let kind: RuleKind
    @State var rule: Rule
    let isNew: Bool
    let onSave: (Rule) -> Void
    let onDelete: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Text(isNew ? "New \(kind == .link ? "Link" : "File") Rule" : "Edit Rule")
                .font(.headline)
                .padding(.top, 18)

            Form {
                Section {
                    TextField("Name", text: $rule.name, prompt: Text("Optional"))
                }

                Section {
                    if rule.conditions.count > 1 {
                        Picker("Match", selection: $rule.requiresAll) {
                            Text("All of these conditions").tag(true)
                            Text("Any of these conditions").tag(false)
                        }
                    }
                    ForEach($rule.conditions) { $condition in
                        ConditionRow(
                            kind: kind,
                            condition: $condition,
                            canRemove: rule.conditions.count > 1,
                            remove: { rule.conditions.removeAll { $0.id == condition.id } }
                        )
                    }
                    Button {
                        let field = ConditionField.fields(for: kind)[0]
                        rule.conditions.append(Condition(field, field.operators[0], ""))
                    } label: {
                        Label("Add Condition", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text(kind == .link ? "When a link…" : "When a file…")
                }

                Section("Then") {
                    switch kind {
                    case .link: LinkTargetPicker(action: $rule.action)
                    case .file: FileTargetPicker(action: $rule.action, conditions: rule.conditions)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                if !isNew {
                    Button("Delete Rule", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Rule" : "Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
            .padding(16)
        }
        .frame(width: 620, height: 500)
    }

    private var canSave: Bool {
        rule.isComplete && rule.conditions.allSatisfy { $0.op.validationError(for: $0.trimmedValue) == nil }
    }
}

private struct ConditionRow: View {
    let kind: RuleKind
    @Binding var condition: Condition
    let canRemove: Bool
    let remove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Picker("Field", selection: fieldBinding) {
                    ForEach(ConditionField.fields(for: kind), id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()

                Picker("Operator", selection: $condition.op) {
                    ForEach(condition.field.operators, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()

                valueEditor
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: remove) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .opacity(canRemove ? 1 : 0)
                .help("Remove condition")
            }

            if let error = condition.op.validationError(for: condition.trimmedValue) {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Switching field resets the operator and value, since they rarely carry over meaningfully.
    private var fieldBinding: Binding<ConditionField> {
        Binding(
            get: { condition.field },
            set: { field in
                guard field != condition.field else { return }
                condition.field = field
                condition.op = field.operators[0]
                condition.value = ""
            }
        )
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch condition.field {
        case .sourceApp:
            AppChooser(bundleID: $condition.value, candidates: AppCatalog.runningApps(), placeholder: "Choose App")
        case .folder:
            FolderChooser(path: $condition.value)
        default:
            TextField("Value", text: $condition.value,
                      prompt: Text(RuleDescriptions.placeholder(for: condition.field, op: condition.op)))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
        }
    }

    private var hint: String? {
        switch (condition.field, condition.op) {
        case (.domain, .is), (.domain, .isNot): "Includes subdomains. Use * as a wildcard."
        case (.url, .matchesPattern), (.fileName, .matchesPattern): "Use * to match anything."
        case (.fileExtension, _): "Separate several with commas."
        case (.folder, _): "Includes everything in subfolders."
        default: nil
        }
    }
}

private struct LinkTargetPicker: View {
    @Binding var action: RuleAction
    @Environment(AppModel.self) private var model

    var body: some View {
        Picker("Open in", selection: $action) {
            Label("Ask Me", systemImage: "questionmark.circle").tag(RuleAction.ask)
            Divider()
            ForEach(model.orderedBrowsers) { browser in
                Label {
                    Text(browser.fullTitle)
                } icon: {
                    Image(nsImage: MenuIcons.browser(browser))
                }
                .tag(RuleAction.open(browser.target))
            }
            if let target = action.target, !model.browsers.contains(where: { $0.target == target }) {
                Text("Missing: \(target.key)").tag(action)
            }
        }
    }
}

private struct FileTargetPicker: View {
    @Binding var action: RuleAction
    let conditions: [Condition]
    @Environment(AppModel.self) private var model

    var body: some View {
        LabeledContent("Open with") {
            AppChooser(
                bundleID: Binding(
                    get: { action.target?.bundleID ?? "" },
                    set: { action = $0.isEmpty ? .ask : .open(Target(bundleID: $0)) }
                ),
                candidates: candidates,
                placeholder: "Ask Me",
                allowsAsk: true
            )
        }
    }

    /// Apps that can open the extensions this rule mentions, or the file types Portrero handles.
    private var candidates: [AppInfo] {
        var types = conditions
            .filter { $0.field == .fileExtension && $0.op == .is }
            .flatMap { FileMatcher.extensions(in: $0.value) }
            .compactMap { UTType(filenameExtension: $0) }
        if types.isEmpty {
            types = model.config.handledFileTypes.compactMap { UTType($0.identifier) }
        }
        var seen = Set<String>()
        return types.flatMap(AppCatalog.apps(toOpen:))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// Pick an app from a list, or anything in /Applications via "Other…". Stores the bundle ID.
struct AppChooser: View {
    @Binding var bundleID: String
    let candidates: [AppInfo]
    let placeholder: String
    var allowsAsk = false

    var body: some View {
        Menu {
            if allowsAsk {
                Button {
                    bundleID = ""
                } label: {
                    Label("Ask Me", systemImage: "questionmark.circle")
                }
                Divider()
            }
            ForEach(candidates) { app in
                Button {
                    bundleID = app.bundleID ?? ""
                } label: {
                    Label { Text(app.name) } icon: { Image(nsImage: MenuIcons.app(app)) }
                }
            }
            if !candidates.isEmpty { Divider() }
            Button("Other…") {
                if let id = Self.chooseApplication()?.bundleID { bundleID = id }
            }
        } label: {
            if let app = AppCatalog.info(bundleID: bundleID) {
                Label { Text(app.name) } icon: { Image(nsImage: MenuIcons.app(app)) }
            } else {
                Text(bundleID.isEmpty ? placeholder : bundleID)
            }
        }
        .fixedSize()
    }

    static func chooseApplication() -> AppInfo? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return AppCatalog.info(at: url)
    }
}

private struct FolderChooser: View {
    @Binding var path: String
    @State private var isTargeted = false

    var body: some View {
        HStack(spacing: 8) {
            if path.isEmpty {
                Text("Choose or drop a folder")
                    .foregroundStyle(.secondary)
            } else {
                Label {
                    Text((path as NSString).abbreviatingWithTildeInPath)
                        .lineLimit(1)
                        .truncationMode(.head)
                } icon: {
                    Image(nsImage: MenuIcons.resized(NSWorkspace.shared.icon(forFile: (path as NSString).expandingTildeInPath)))
                }
                .help(path)
            }
            Spacer(minLength: 4)
            Button("Choose…", action: choose)
        }
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).opacity(isTargeted ? 1 : 0)
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            else { return false }
            path = url.path(percentEncoded: false)
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Choose"
        if !path.isEmpty { panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath) }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path(percentEncoded: false)
        }
    }
}
