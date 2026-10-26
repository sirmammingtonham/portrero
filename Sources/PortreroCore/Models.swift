import Foundation

/// Where a link or file should go: an app, optionally narrowed to one browser profile.
public struct Target: Codable, Hashable, Sendable {
    public var bundleID: String
    /// Chromium profile directory (e.g. "Profile 1") or Firefox profile name.
    public var profile: String?

    public init(bundleID: String, profile: String? = nil) {
        self.bundleID = bundleID
        self.profile = profile
    }

    /// Stable identifier used to order and hide browsers in settings.
    public var key: String {
        profile.map { "\(bundleID)#\($0)" } ?? bundleID
    }
}

/// What to do once a rule matches (or when nothing matches).
public enum RuleAction: Hashable, Sendable {
    /// Show the picker.
    case ask
    case open(Target)

    public var target: Target? {
        if case .open(let target) = self { return target }
        return nil
    }
}

extension RuleAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, target }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "open": self = .open(try container.decode(Target.self, forKey: .target))
        default: self = .ask
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .ask:
            try container.encode("ask", forKey: .type)
        case .open(let target):
            try container.encode("open", forKey: .type)
            try container.encode(target, forKey: .target)
        }
    }
}

public enum RuleKind: String, Codable, Sendable {
    case link, file
}

public enum ConditionField: String, Codable, CaseIterable, Sendable {
    case domain, url, sourceApp, fileExtension, folder, fileName

    public static func fields(for kind: RuleKind) -> [ConditionField] {
        switch kind {
        case .link: [.domain, .url, .sourceApp]
        case .file: [.fileExtension, .folder, .fileName, .sourceApp]
        }
    }

    public var operators: [ConditionOperator] {
        switch self {
        case .domain: [.is, .isNot, .contains]
        case .url: [.contains, .startsWith, .matchesPattern, .matchesRegex]
        case .sourceApp: [.is, .isNot]
        case .fileExtension: [.is, .isNot]
        case .folder: [.isInside, .isNotInside]
        case .fileName: [.contains, .matchesPattern, .matchesRegex]
        }
    }

    public var title: String {
        switch self {
        case .domain: "Domain"
        case .url: "URL"
        case .sourceApp: "Source app"
        case .fileExtension: "Extension"
        case .folder: "Location"
        case .fileName: "File name"
        }
    }
}

public enum ConditionOperator: String, Codable, CaseIterable, Sendable {
    case `is`, isNot, contains, startsWith, matchesPattern, matchesRegex, isInside, isNotInside

    public var title: String {
        switch self {
        case .is: "is"
        case .isNot: "is not"
        case .contains: "contains"
        case .startsWith: "starts with"
        case .matchesPattern: "matches pattern"
        case .matchesRegex: "matches regex"
        case .isInside: "is inside"
        case .isNotInside: "is not inside"
        }
    }
}

public struct Condition: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var field: ConditionField
    public var op: ConditionOperator
    public var value: String

    public init(id: UUID = UUID(), _ field: ConditionField, _ op: ConditionOperator, _ value: String) {
        self.id = id
        self.field = field
        self.op = op
        self.value = value
    }

    public var trimmedValue: String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isComplete: Bool { !trimmedValue.isEmpty }

    /// Equality that ignores the id and insignificant differences in the value.
    public func isEquivalent(to other: Condition) -> Bool {
        field == other.field && op == other.op
            && trimmedValue.lowercased() == other.trimmedValue.lowercased()
    }
}

public struct Rule: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    /// Optional; the UI falls back to a summary of the conditions.
    public var name: String
    public var isEnabled: Bool
    /// `true` = every condition must match, `false` = any one condition.
    public var requiresAll: Bool
    public var conditions: [Condition]
    public var action: RuleAction

    public init(
        id: UUID = UUID(),
        name: String = "",
        isEnabled: Bool = true,
        requiresAll: Bool = true,
        conditions: [Condition],
        action: RuleAction
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.requiresAll = requiresAll
        self.conditions = conditions
        self.action = action
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        requiresAll = try c.decodeIfPresent(Bool.self, forKey: .requiresAll) ?? true
        conditions = try c.decodeIfPresent([Condition].self, forKey: .conditions) ?? []
        action = try c.decodeIfPresent(RuleAction.self, forKey: .action) ?? .ask
    }

    /// Incomplete rules (no conditions, or an empty value) never match.
    public var isComplete: Bool {
        !conditions.isEmpty && conditions.allSatisfy(\.isComplete)
    }

    public func hasEquivalentConditions(to other: [Condition]) -> Bool {
        conditions.count == other.count
            && conditions.allSatisfy { mine in other.contains { $0.isEquivalent(to: mine) } }
    }
}

public enum PickerPlacement: String, Codable, CaseIterable, Sendable {
    case mousePointer, screenCenter
}

/// A file type Portrero has made itself the default handler for.
public struct HandledFileType: Codable, Hashable, Identifiable, Sendable {
    /// Uniform Type Identifier, e.g. "public.json".
    public var identifier: String
    /// The app that was the default before Portrero took over; restored on removal.
    public var previousHandlerBundleID: String?

    public var id: String { identifier }

    public init(identifier: String, previousHandlerBundleID: String?) {
        self.identifier = identifier
        self.previousHandlerBundleID = previousHandlerBundleID
    }
}

public struct Config: Codable, Equatable, Sendable {
    public var linkRules: [Rule] = []
    public var fileRules: [Rule] = []
    /// What happens to a link that no rule matches.
    public var linkFallback: RuleAction = .ask
    /// `Target.key`s in the order the user arranged them. Unknown browsers go last.
    public var browserOrder: [String] = []
    public var hiddenBrowsers: Set<String> = []
    /// Apps that are hidden until switched on (ones that take web links but aren't browsers).
    public var shownBrowsers: Set<String> = []
    /// The default browser before Portrero took over, which leads the list from then on.
    public var previousDefaultBrowser: String?
    public var stripTrackingParameters = true
    public var pickerPlacement: PickerPlacement = .mousePointer
    public var showMenuBarIcon = true
    public var handledFileTypes: [HandledFileType] = []
    public var hasCompletedOnboarding = false

    public init() {}

    // Every key is optional so older config files keep loading as settings are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Config()
        linkRules = try c.decodeIfPresent([Rule].self, forKey: .linkRules) ?? defaults.linkRules
        fileRules = try c.decodeIfPresent([Rule].self, forKey: .fileRules) ?? defaults.fileRules
        linkFallback = try c.decodeIfPresent(RuleAction.self, forKey: .linkFallback) ?? defaults.linkFallback
        browserOrder = try c.decodeIfPresent([String].self, forKey: .browserOrder) ?? defaults.browserOrder
        hiddenBrowsers = try c.decodeIfPresent(Set<String>.self, forKey: .hiddenBrowsers) ?? defaults.hiddenBrowsers
        shownBrowsers = try c.decodeIfPresent(Set<String>.self, forKey: .shownBrowsers) ?? defaults.shownBrowsers
        previousDefaultBrowser = try c.decodeIfPresent(String.self, forKey: .previousDefaultBrowser)
        stripTrackingParameters = try c.decodeIfPresent(Bool.self, forKey: .stripTrackingParameters)
            ?? defaults.stripTrackingParameters
        pickerPlacement = (try? c.decodeIfPresent(PickerPlacement.self, forKey: .pickerPlacement))
            ?? defaults.pickerPlacement
        showMenuBarIcon = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? defaults.showMenuBarIcon
        handledFileTypes = try c.decodeIfPresent([HandledFileType].self, forKey: .handledFileTypes)
            ?? defaults.handledFileTypes
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? defaults.hasCompletedOnboarding
    }

    public func rules(for kind: RuleKind) -> [Rule] {
        kind == .link ? linkRules : fileRules
    }

    public mutating func setRules(_ rules: [Rule], for kind: RuleKind) {
        if kind == .link { linkRules = rules } else { fileRules = rules }
    }
}
