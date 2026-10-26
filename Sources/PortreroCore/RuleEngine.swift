import Foundation

/// Something the user (or another app) asked macOS to open.
public enum OpenRequest: Sendable {
    case link(URL, sourceBundleID: String?)
    case file(URL, sourceBundleID: String?)

    public var sourceBundleID: String? {
        switch self {
        case .link(_, let source), .file(_, let source): source
        }
    }
}

public enum RuleEngine {
    /// Rules are evaluated top to bottom; the first enabled, matching rule wins.
    public static func firstMatch(in rules: [Rule], for request: OpenRequest) -> Rule? {
        rules.first { $0.isEnabled && matches($0, request) }
    }

    public static func matches(_ rule: Rule, _ request: OpenRequest) -> Bool {
        guard rule.isComplete else { return false }
        return rule.requiresAll
            ? rule.conditions.allSatisfy { evaluate($0, request) }
            : rule.conditions.contains { evaluate($0, request) }
    }

    public static func evaluate(_ condition: Condition, _ request: OpenRequest) -> Bool {
        let value = condition.trimmedValue
        guard !value.isEmpty else { return false }

        switch (condition.field, request) {
        case (.domain, .link(let url, _)):
            guard let host = DomainMatcher.host(of: url) else { return false }
            switch condition.op {
            case .is: return DomainMatcher.matches(host: host, pattern: value)
            case .isNot: return !DomainMatcher.matches(host: host, pattern: value)
            case .contains: return host.contains(value.lowercased())
            default: return false
            }

        case (.url, .link(let url, _)):
            return URLMatcher.evaluate(condition.op, url: url, value: value)

        case (.sourceApp, _):
            let source = request.sourceBundleID?.lowercased()
            switch condition.op {
            case .is: return source == value.lowercased()
            case .isNot: return source != value.lowercased()
            default: return false
            }

        case (.fileExtension, .file(let url, _)):
            let matched = FileMatcher.hasExtension(url, in: value)
            switch condition.op {
            case .is: return matched
            case .isNot: return !matched
            default: return false
            }

        case (.folder, .file(let url, _)):
            let inside = FileMatcher.isFile(url, inside: value)
            switch condition.op {
            case .isInside: return inside
            case .isNotInside: return !inside
            default: return false
            }

        case (.fileName, .file(let url, _)):
            let name = url.lastPathComponent
            switch condition.op {
            case .contains: return name.localizedCaseInsensitiveContains(value)
            case .matchesPattern: return Pattern.wildcard(value, matches: name)
            case .matchesRegex: return Pattern.regex(value, matches: name)
            default: return false
            }

        default:
            // Field doesn't apply to this kind of request (e.g. a domain condition on a file).
            return false
        }
    }
}

public enum DomainMatcher {
    /// Turns whatever the user typed or pasted ("https://www.GitHub.com/foo") into a bare host ("github.com").
    public static func normalize(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if let end = s.firstIndex(where: { "/?#".contains($0) }) { s = String(s[..<end]) }
        if let at = s.lastIndex(of: "@") { s = String(s[s.index(after: at)...]) }
        if let colon = s.lastIndex(of: ":"), s[s.index(after: colon)...].allSatisfy(\.isNumber) {
            s = String(s[..<colon])
        }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        while s.hasSuffix(".") { s.removeLast() }
        return s
    }

    public static func host(of url: URL) -> String? {
        guard let host = url.host(percentEncoded: false), !host.isEmpty else { return nil }
        return normalize(host)
    }

    /// `github.com` matches github.com and every subdomain; `*` wildcards are honoured when present.
    public static func matches(host: String, pattern: String) -> Bool {
        let host = normalize(host)
        let pattern = normalize(pattern)
        guard !pattern.isEmpty else { return false }
        if pattern.contains("*") { return Pattern.wildcard(pattern, matches: host) }
        return host == pattern || host.hasSuffix("." + pattern)
    }
}

enum URLMatcher {
    static func evaluate(_ op: ConditionOperator, url: URL, value: String) -> Bool {
        let full = url.absoluteString
        switch op {
        case .contains:
            return full.localizedCaseInsensitiveContains(value)
        case .startsWith:
            // Let people omit the scheme and "www." ("github.com/my-org" should just work).
            return full.lowercased().hasPrefix(value.lowercased())
                || bare(full).hasPrefix(bare(value))
        case .matchesPattern:
            return Pattern.wildcard(value, matches: full)
                || Pattern.wildcard(bare(value), matches: bare(full))
        case .matchesRegex:
            return Pattern.regex(value, matches: full)
        default:
            return false
        }
    }

    private static func bare(_ s: String) -> String {
        var s = s.lowercased()
        if let scheme = s.range(of: "://") { s = String(s[scheme.upperBound...]) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        return s
    }
}

public enum FileMatcher {
    /// Accepts "json", ".json", "*.json" and lists like "yaml, yml". Supports compound extensions ("tar.gz").
    public static func extensions(in value: String) -> [String] {
        value
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map { part -> String in
                var ext = part.lowercased()
                while ext.hasPrefix("*") || ext.hasPrefix(".") { ext.removeFirst() }
                return ext
            }
            .filter { !$0.isEmpty }
    }

    public static func hasExtension(_ url: URL, in value: String) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return extensions(in: value).contains { name.hasSuffix("." + $0) }
    }

    public static func isFile(_ url: URL, inside folder: String) -> Bool {
        let folderPath = canonicalPath((folder as NSString).expandingTildeInPath).lowercased()
        let filePath = canonicalPath(url.path(percentEncoded: false)).lowercased()
        if folderPath == "/" { return true }
        return filePath.hasPrefix(folderPath + "/")
    }

    static func canonicalPath(_ path: String) -> String {
        var resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
            .path(percentEncoded: false)
        while resolved.count > 1 && resolved.hasSuffix("/") { resolved.removeLast() }
        return resolved
    }
}

enum Pattern {
    /// Glob-style match where `*` means "anything". Anchored and case-insensitive.
    static func wildcard(_ pattern: String, matches subject: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: pattern)
            .replacingOccurrences(of: "\\*", with: ".*")
        return regex("^\(escaped)$", matches: subject)
    }

    /// Unanchored, case-insensitive. Invalid expressions simply don't match.
    static func regex(_ pattern: String, matches subject: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(subject.startIndex..., in: subject)
        return expression.firstMatch(in: subject, range: range) != nil
    }

    public static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }
}

public extension ConditionOperator {
    /// Lets the editor flag a broken regex while the user types.
    func validationError(for value: String) -> String? {
        guard self == .matchesRegex, !value.isEmpty, !Pattern.isValidRegex(value) else { return nil }
        return "This isn’t a valid regular expression."
    }
}
