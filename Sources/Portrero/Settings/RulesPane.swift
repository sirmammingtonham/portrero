import PortreroCore
import SwiftUI

struct RulesPane: View {
    let kind: RuleKind
    @Environment(AppModel.self) private var model
    @State private var editing: EditingRule?

    private struct EditingRule: Identifiable {
        var rule: Rule
        var isNew: Bool
        var id: UUID { rule.id }
    }

    var body: some View {
        let rules = model.config.rules(for: kind)

        Form {
            Section {
                if rules.isEmpty {
                    EmptyRules(kind: kind, add: addRule)
                }
                ForEach(rules) { rule in
                    RuleRow(rule: rule, kind: kind, edit: { edit(rule) })
                        .contextMenu {
                            Button("Edit…") { edit(rule) }
                            Button("Duplicate") { duplicate(rule) }
                            Divider()
                            Button("Delete", role: .destructive) { model.deleteRule(id: rule.id, kind: kind) }
                        }
                }
                .onMove { model.moveRules(kind: kind, fromOffsets: $0, toOffset: $1) }
            } header: {
                if !rules.isEmpty {
                    Text("Checked from top to bottom — the first match wins")
                }
            } footer: {
                if !rules.isEmpty {
                    Text(kind == .link
                         ? "Links that don’t match any rule follow the “When no rule matches” setting in General."
                         : "Files that don’t match any rule show the picker.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if kind == .link {
                RuleTester()
            }
        }
        .formStyle(.grouped)
        .toolbar {
            Button(action: addRule) {
                Label("Add Rule", systemImage: "plus")
            }
            .help("Add a rule")
        }
        .sheet(item: $editing) { editing in
            RuleEditor(
                kind: kind,
                rule: editing.rule,
                isNew: editing.isNew,
                onSave: { model.save($0, kind: kind) },
                onDelete: { model.deleteRule(id: editing.rule.id, kind: kind) }
            )
            .environment(model)
        }
    }

    private func addRule() {
        let rule: Rule
        switch kind {
        case .link:
            rule = Rule(conditions: [Condition(.domain, .is, "")],
                        action: model.pickerBrowsers.first.map { .open($0.target) } ?? .ask)
        case .file:
            rule = Rule(conditions: [Condition(.fileExtension, .is, "")], action: .ask)
        }
        editing = EditingRule(rule: rule, isNew: true)
    }

    private func edit(_ rule: Rule) {
        editing = EditingRule(rule: rule, isNew: false)
    }

    private func duplicate(_ rule: Rule) {
        var copy = rule
        copy.id = UUID()
        copy.conditions = rule.conditions.map { Condition($0.field, $0.op, $0.value) }
        editing = EditingRule(rule: copy, isNew: true)
    }
}

private struct EmptyRules: View {
    let kind: RuleKind
    let add: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            SettingsIcon(symbol: kind == .link ? "link" : "folder.fill", color: kind == .link ? .indigo : .teal, size: 40)
            Text("No \(kind == .link ? "Link" : "File") Rules")
                .font(.headline)
            Text(kind == .link
                 ? "Rules send matching links straight to a browser or profile — say, github.com to your work profile. You can also tick “Always open … here” in the picker."
                 : "Rules send matching files straight to an app — say, .json files in your projects folder to your code editor. You can also tick “Always open … here” in the picker.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Add Rule…", action: add)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

private struct RuleRow: View {
    let rule: Rule
    let kind: RuleKind
    let edit: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            RuleTargetIcon(action: rule.action, kind: kind, size: 26)
                .opacity(rule.isEnabled ? 1 : 0.4)

            VStack(alignment: .leading, spacing: 2) {
                Text(RuleDescriptions.title(of: rule))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .foregroundStyle(rule.isEnabled ? .primary : .secondary)

            Spacer(minLength: 8)

            Toggle("Enabled", isOn: Binding(
                get: { rule.isEnabled },
                set: { enabled in
                    var updated = rule
                    updated.isEnabled = enabled
                    model.save(updated, kind: kind)
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)

            Button(action: edit) {
                Image(systemName: "info.circle")
            }
            .buttonStyle(.borderless)
            .help("Edit rule")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: edit)
    }

    private var subtitle: String {
        let destination = RuleTargetDescription.text(for: rule.action, kind: kind, model: model)
        return rule.name.isEmpty ? destination : "\(RuleDescriptions.summary(of: rule)) · \(destination)"
    }
}

@MainActor
enum RuleTargetDescription {
    static func text(for action: RuleAction, kind: RuleKind, model: AppModel) -> String {
        guard let target = action.target else { return "Ask every time" }
        switch kind {
        case .link:
            return model.browser(for: target).map { "Opens in \($0.fullTitle)" } ?? "Browser not found"
        case .file:
            return AppCatalog.info(bundleID: target.bundleID).map { "Opens with \($0.name)" } ?? "App not found"
        }
    }
}

struct RuleTargetIcon: View {
    let action: RuleAction
    let kind: RuleKind
    var size: CGFloat = 24
    @Environment(AppModel.self) private var model

    var body: some View {
        if let target = action.target {
            switch kind {
            case .link:
                if let browser = model.browser(for: target) {
                    BrowserIcon(browser: browser, size: size)
                } else {
                    missing
                }
            case .file:
                if let app = AppCatalog.info(bundleID: target.bundleID) {
                    AppIcon(image: app.icon, size: size)
                } else {
                    missing
                }
            }
        } else {
            SettingsIcon(symbol: "questionmark", color: .gray, size: size * 0.85)
                .frame(width: size, height: size)
        }
    }

    private var missing: some View {
        SettingsIcon(symbol: "exclamationmark", color: .orange, size: size * 0.85)
            .frame(width: size, height: size)
    }
}

private struct RuleTester: View {
    @Environment(AppModel.self) private var model
    @State private var input = ""

    var body: some View {
        Section {
            TextField("Link", text: $input, prompt: Text("Paste a link to see where it would open"))
            if let url {
                let (rule, action) = model.resolve(.link(url, sourceBundleID: nil))
                HStack(spacing: 10) {
                    RuleTargetIcon(action: action, kind: .link, size: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.target == nil ? "Portrero will ask" : RuleTargetDescription.text(for: action, kind: .link, model: model))
                        Text(rule.map { "Matches “\(RuleDescriptions.title(of: $0))”" } ?? "No rule matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Try It")
        }
    }

    private var url: URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let candidate = text.contains("://") ? text : "https://\(text)"
        guard let url = URL(string: candidate), url.host() != nil else { return nil }
        return url
    }
}
