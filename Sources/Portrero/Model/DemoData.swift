#if DEBUG
import AppKit
import PortreroCore

/// Debug builds only: `Portrero --demo` swaps in made-up profiles and rules (and a throwaway config
/// file) so screenshots never show anyone's real accounts.
///
///   open -n build/Portrero.app --args --demo
@MainActor
enum DemoData {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--demo")

    static let configURL = FileManager.default.temporaryDirectory.appending(path: "PortreroDemo/config.json")

    private static let chrome = "com.google.Chrome"

    static func browsers() -> [Browser] {
        var browsers: [Browser] = []
        if let url = AppCatalog.info(bundleID: chrome)?.url {
            let profiles = [
                ("Default", "Work", "you@company.com", NSColor.systemBlue),
                ("Profile 1", "Personal", "you@gmail.com", NSColor.systemOrange),
            ]
            for (id, name, email, color) in profiles {
                browsers.append(Browser(
                    target: Target(bundleID: chrome, profile: id), appURL: url, appName: "Google Chrome",
                    profileName: name, profileDetail: email, engine: .chromium,
                    avatar: .init(image: nil, color: color, initial: String(name.prefix(1))), isWebBrowser: true
                ))
            }
        }
        for (bundleID, engine) in [("com.apple.Safari", Browser.Engine.other), ("org.mozilla.firefox", .firefox)] {
            guard let url = AppCatalog.info(bundleID: bundleID)?.url else { continue }
            browsers.append(Browser(
                target: Target(bundleID: bundleID), appURL: url, appName: AppCatalog.displayName(of: url),
                profileName: nil, profileDetail: nil, engine: engine, avatar: nil, isWebBrowser: true
            ))
        }
        return browsers
    }

    static func config() -> Config {
        var config = Config()
        config.hasCompletedOnboarding = true
        config.pickerPlacement = .screenCenter
        let work = RuleAction.open(Target(bundleID: chrome, profile: "Default"))
        let personal = RuleAction.open(Target(bundleID: chrome, profile: "Profile 1"))
        config.linkRules = [
            Rule(name: "Work code", conditions: [Condition(.domain, .is, "github.com")], action: work),
            Rule(name: "From Slack", conditions: [Condition(.sourceApp, .is, "com.tinyspeck.slackmacgap")], action: work),
            Rule(requiresAll: false, conditions: [Condition(.domain, .is, "youtube.com"), Condition(.domain, .is, "reddit.com")],
                 action: personal),
            Rule(conditions: [Condition(.url, .contains, "docs.google.com/a/company.com")], action: work),
        ]
        let editor = AppCatalog.info(bundleID: "com.microsoft.VSCode")?.url != nil ? "com.microsoft.VSCode" : "com.apple.TextEdit"
        config.fileRules = [
            Rule(name: "Project files", conditions: [Condition(.fileExtension, .is, "json"), Condition(.folder, .isInside, "~/Developer")],
                 action: .open(Target(bundleID: editor))),
            Rule(conditions: [Condition(.fileExtension, .is, "md")], action: .ask),
        ]
        return config
    }
}
#endif
