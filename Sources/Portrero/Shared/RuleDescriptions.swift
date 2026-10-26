import Foundation
import PortreroCore

/// Human-readable text for rules, e.g. "Domain is github.com and Source app is Slack".
@MainActor
enum RuleDescriptions {
    static func title(of rule: Rule) -> String {
        rule.name.isEmpty ? summary(of: rule) : rule.name
    }

    static func summary(of rule: Rule) -> String {
        guard !rule.conditions.isEmpty else { return "No conditions" }
        return rule.conditions.map(describe).joined(separator: rule.requiresAll ? " and " : " or ")
    }

    static func describe(_ condition: Condition) -> String {
        "\(condition.field.title) \(condition.op.title) \(displayValue(of: condition))"
    }

    static func displayValue(of condition: Condition) -> String {
        let value = condition.trimmedValue
        guard !value.isEmpty else { return "…" }
        switch condition.field {
        case .sourceApp:
            return AppCatalog.name(forBundleID: value)
        case .folder:
            return (value as NSString).abbreviatingWithTildeInPath
        case .fileExtension:
            return FileMatcher.extensions(in: value).map { ".\($0)" }.joined(separator: ", ")
        case .domain:
            return DomainMatcher.normalize(value)
        case .url, .fileName:
            return value
        }
    }

    static func placeholder(for field: ConditionField, op: ConditionOperator) -> String {
        switch (field, op) {
        case (.domain, _): "github.com"
        case (.url, .matchesRegex): #"github\.com/.+/pull/\d+"#
        case (.url, .matchesPattern): "github.com/my-org/*"
        case (.url, _): "github.com/my-org"
        case (.fileExtension, _): "json, yaml"
        case (.fileName, .matchesPattern): "*.test.json"
        case (.fileName, .matchesRegex): #"^\d{4}-"#
        case (.fileName, _): "README"
        case (.sourceApp, _), (.folder, _): ""
        }
    }
}
