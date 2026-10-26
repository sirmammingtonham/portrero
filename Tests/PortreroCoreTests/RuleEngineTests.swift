import Foundation
import Testing
@testable import PortreroCore

private let work = Target(bundleID: "com.google.Chrome", profile: "Profile 1")
private let personal = Target(bundleID: "com.google.Chrome", profile: "Default")

private func link(_ string: String, from source: String? = nil) -> OpenRequest {
    .link(URL(string: string)!, sourceBundleID: source)
}

private func file(_ path: String, from source: String? = nil) -> OpenRequest {
    .file(URL(fileURLWithPath: path), sourceBundleID: source)
}

private func rule(_ conditions: Condition..., requiresAll: Bool = true, to target: Target = work) -> Rule {
    Rule(requiresAll: requiresAll, conditions: conditions, action: .open(target))
}

@Suite struct DomainMatching {
    @Test(arguments: [
        ("https://github.com/apple", true),
        ("https://www.github.com", true),
        ("https://gist.github.com/x", true),
        ("https://GITHUB.COM", true),
        ("https://notgithub.com", false),
        ("https://github.com.evil.example", false),
    ])
    func domainIsIncludesSubdomains(url: String, expected: Bool) {
        let condition = Condition(.domain, .is, "github.com")
        #expect(RuleEngine.evaluate(condition, link(url)) == expected)
    }

    @Test func pastedURLsAreNormalizedToHosts() {
        #expect(DomainMatcher.normalize("  https://www.GitHub.com:443/foo?bar#baz ") == "github.com")
        #expect(DomainMatcher.normalize("user@docs.google.com") == "docs.google.com")
        #expect(DomainMatcher.normalize("example.com.") == "example.com")
    }

    @Test func wildcardPatterns() {
        let condition = Condition(.domain, .is, "*.google.com")
        #expect(RuleEngine.evaluate(condition, link("https://docs.google.com")))
        #expect(!RuleEngine.evaluate(condition, link("https://google.com")))
        #expect(RuleEngine.evaluate(Condition(.domain, .is, "docs.google.*"), link("https://docs.google.co.uk/x")))
    }

    @Test func isNotAndContains() {
        #expect(RuleEngine.evaluate(Condition(.domain, .isNot, "github.com"), link("https://youtube.com")))
        #expect(!RuleEngine.evaluate(Condition(.domain, .isNot, "github.com"), link("https://github.com")))
        #expect(RuleEngine.evaluate(Condition(.domain, .contains, "atlassian"), link("https://acme.atlassian.net")))
    }
}

@Suite struct URLMatching {
    @Test func contains() {
        let condition = Condition(.url, .contains, "/pull/")
        #expect(RuleEngine.evaluate(condition, link("https://github.com/a/b/pull/1")))
        #expect(!RuleEngine.evaluate(condition, link("https://github.com/a/b/issues/1")))
    }

    @Test func startsWithIgnoresSchemeAndWWW() {
        let condition = Condition(.url, .startsWith, "github.com/my-org")
        #expect(RuleEngine.evaluate(condition, link("https://www.github.com/my-org/repo")))
        #expect(RuleEngine.evaluate(Condition(.url, .startsWith, "https://github.com/my-org"), link("https://github.com/my-org/x")))
        #expect(!RuleEngine.evaluate(condition, link("https://github.com/other-org")))
    }

    @Test func patternAndRegex() {
        #expect(RuleEngine.evaluate(Condition(.url, .matchesPattern, "github.com/*/pull/*"), link("https://github.com/a/pull/3")))
        #expect(RuleEngine.evaluate(Condition(.url, .matchesRegex, #"youtube\.com/watch\?v="#), link("https://www.youtube.com/watch?v=abc")))
        #expect(!RuleEngine.evaluate(Condition(.url, .matchesRegex, "(unclosed"), link("https://example.com")))
    }

    @Test func regexValidation() {
        #expect(ConditionOperator.matchesRegex.validationError(for: "(unclosed") != nil)
        #expect(ConditionOperator.matchesRegex.validationError(for: "ok.*") == nil)
        #expect(ConditionOperator.contains.validationError(for: "(") == nil)
    }
}

@Suite struct SourceAppMatching {
    @Test func matchesBundleIDCaseInsensitively() {
        let condition = Condition(.sourceApp, .is, "com.tinyspeck.slackmacgap")
        #expect(RuleEngine.evaluate(condition, link("https://x.com", from: "com.tinyspeck.SlackMacGap")))
        #expect(!RuleEngine.evaluate(condition, link("https://x.com", from: "com.apple.mail")))
        #expect(!RuleEngine.evaluate(condition, link("https://x.com")))
    }

    @Test func isNotTreatsUnknownSourceAsNotMatching() {
        let condition = Condition(.sourceApp, .isNot, "com.apple.mail")
        #expect(RuleEngine.evaluate(condition, link("https://x.com")))
        #expect(!RuleEngine.evaluate(condition, link("https://x.com", from: "com.apple.mail")))
    }

    @Test func appliesToFilesToo() {
        let condition = Condition(.sourceApp, .is, "com.apple.finder")
        #expect(RuleEngine.evaluate(condition, file("/tmp/a.json", from: "com.apple.finder")))
    }
}

@Suite struct FileMatching {
    @Test func extensionLists() {
        #expect(FileMatcher.extensions(in: ".json, *.YAML yml") == ["json", "yaml", "yml"])
        let condition = Condition(.fileExtension, .is, "yaml, yml")
        #expect(RuleEngine.evaluate(condition, file("/x/config.YML")))
        #expect(!RuleEngine.evaluate(condition, file("/x/config.json")))
        #expect(RuleEngine.evaluate(Condition(.fileExtension, .is, "tar.gz"), file("/x/a.tar.gz")))
        #expect(RuleEngine.evaluate(Condition(.fileExtension, .isNot, "json"), file("/x/a.md")))
    }

    @Test func folderContainment() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "portrero-tests-\(UUID().uuidString)")
        let nested = root.appending(path: "Work/project")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let inside = Condition(.folder, .isInside, root.appending(path: "Work").path + "/")
        #expect(RuleEngine.evaluate(inside, .file(nested.appending(path: "a.json"), sourceBundleID: nil)))
        #expect(!RuleEngine.evaluate(inside, .file(root.appending(path: "Workshop/a.json"), sourceBundleID: nil)))
        #expect(!RuleEngine.evaluate(inside, .file(root.appending(path: "Work"), sourceBundleID: nil)))

        let outside = Condition(.folder, .isNotInside, root.appending(path: "Work").path)
        #expect(RuleEngine.evaluate(outside, .file(root.appending(path: "b.json"), sourceBundleID: nil)))
    }

    @Test func tildeExpansion() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let condition = Condition(.folder, .isInside, "~/Projects")
        #expect(RuleEngine.evaluate(condition, .file(home.appending(path: "Projects/x/a.json"), sourceBundleID: nil)))
    }

    @Test func fileNames() {
        #expect(RuleEngine.evaluate(Condition(.fileName, .matchesPattern, "*.test.json"), file("/x/api.test.json")))
        #expect(!RuleEngine.evaluate(Condition(.fileName, .matchesPattern, "*.test.json"), file("/x/api.json")))
        #expect(RuleEngine.evaluate(Condition(.fileName, .contains, "README"), file("/x/readme.md")))
        #expect(RuleEngine.evaluate(Condition(.fileName, .matchesRegex, #"^\d{4}-"#), file("/x/2026-notes.md")))
    }

    @Test func linkFieldsNeverMatchFiles() {
        #expect(!RuleEngine.evaluate(Condition(.domain, .isNot, "github.com"), file("/x/a.json")))
        #expect(!RuleEngine.evaluate(Condition(.fileExtension, .isNot, "json"), link("https://a.com/x.md")))
    }
}

@Suite struct Rules {
    @Test func firstEnabledMatchWins() {
        var disabled = rule(Condition(.domain, .is, "github.com"), to: personal)
        disabled.isEnabled = false
        let rules = [
            disabled,
            rule(Condition(.domain, .is, "github.com"), to: work),
            rule(Condition(.domain, .contains, "git"), to: personal),
        ]
        #expect(RuleEngine.firstMatch(in: rules, for: link("https://github.com"))?.action == .open(work))
        #expect(RuleEngine.firstMatch(in: rules, for: link("https://gitlab.com"))?.action == .open(personal))
        #expect(RuleEngine.firstMatch(in: rules, for: link("https://youtube.com")) == nil)
    }

    @Test func allVersusAny() {
        let conditions = [Condition(.domain, .is, "github.com"), Condition(.sourceApp, .is, "com.tinyspeck.slackmacgap")]
        let all = Rule(requiresAll: true, conditions: conditions, action: .ask)
        let any = Rule(requiresAll: false, conditions: conditions, action: .ask)
        let request = link("https://github.com")
        #expect(!RuleEngine.matches(all, request))
        #expect(RuleEngine.matches(any, request))
        #expect(RuleEngine.matches(all, link("https://github.com", from: "com.tinyspeck.slackmacgap")))
    }

    @Test func incompleteRulesNeverMatch() {
        #expect(!RuleEngine.matches(Rule(conditions: [], action: .ask), link("https://a.com")))
        let blank = Rule(conditions: [Condition(.domain, .isNot, "  ")], action: .ask)
        #expect(!RuleEngine.matches(blank, link("https://a.com")))
    }

    @Test func equivalentConditions() {
        let r = rule(Condition(.domain, .is, "GitHub.com "), Condition(.sourceApp, .is, "x"))
        #expect(r.hasEquivalentConditions(to: [Condition(.sourceApp, .is, "x"), Condition(.domain, .is, "github.com")]))
        #expect(!r.hasEquivalentConditions(to: [Condition(.domain, .is, "github.com")]))
    }
}
