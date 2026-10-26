import AppKit
import Observation
import os
import PortreroCore
import ServiceManagement
import UniformTypeIdentifiers

let log = Logger(subsystem: "app.portrero.Portrero", category: "app")

/// Single source of truth for settings and system state, shared by the picker, settings and menu bar.
@MainActor
@Observable
final class AppModel {
    var config: Config {
        didSet { if config != oldValue { store.save(config) } }
    }

    private(set) var browsers: [Browser] = []
    private(set) var isDefaultBrowser = false
    private(set) var launchesAtLogin = false
    /// Handled file types for which Portrero is still the system default.
    private(set) var activeFileTypes: Set<String> = []
    /// The menu bar icon is enabled but covered (usually by the camera notch on a full menu bar).
    var menuBarIconIsHidden = false

    @ObservationIgnored private let store: ConfigStore
    @ObservationIgnored private let isDemo: Bool

    convenience init() {
        #if DEBUG
        if DemoData.isEnabled {
            self.init(store: ConfigStore(fileURL: DemoData.configURL), config: DemoData.config(), isDemo: true)
            return
        }
        #endif
        let store = ConfigStore()
        self.init(store: store, config: store.load(), isDemo: false)
    }

    private init(store: ConfigStore, config: Config, isDemo: Bool) {
        self.store = store
        self.config = config
        self.isDemo = isDemo
    }

    func refresh() {
        #if DEBUG
        if isDemo {
            browsers = DemoData.browsers()
            refreshSystemState()
            return
        }
        #endif
        browsers = BrowserCatalog.discover(preferredBundleID: config.previousDefaultBrowser)
        refreshSystemState()
    }

    func refreshSystemState() {
        isDefaultBrowser = SystemDefaults.isDefaultBrowser
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        activeFileTypes = Set(config.handledFileTypes.map(\.identifier).filter(SystemDefaults.isDefaultHandler(for:)))
    }

    // MARK: - Browsers

    /// All browsers in the user's order. Newly installed browsers go to the end.
    var orderedBrowsers: [Browser] {
        let rank = Dictionary(config.browserOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return browsers.enumerated()
            .sorted { (rank[$0.element.id] ?? .max, $0.offset) < (rank[$1.element.id] ?? .max, $1.offset) }
            .map(\.element)
    }

    /// What the picker shows. Never empty while any browser exists, even if the user hid them all.
    var pickerBrowsers: [Browser] {
        let visible = orderedBrowsers.filter { !isHidden($0) }
        return visible.isEmpty ? orderedBrowsers : visible
    }

    /// Exact profile if it still exists, otherwise the same browser (e.g. after deleting a profile).
    func browser(for target: Target) -> Browser? {
        browsers.first { $0.target == target } ?? browsers.first { $0.target.bundleID == target.bundleID }
    }

    func moveBrowsers(fromOffsets source: IndexSet, toOffset destination: Int) {
        var ids = orderedBrowsers.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        config.browserOrder = ids
    }

    /// Browsers are shown unless hidden; apps that merely accept web links are hidden unless shown.
    func isHidden(_ browser: Browser) -> Bool {
        browser.isWebBrowser ? config.hiddenBrowsers.contains(browser.id) : !config.shownBrowsers.contains(browser.id)
    }

    func setHidden(_ hidden: Bool, _ browser: Browser) {
        if browser.isWebBrowser {
            if hidden { config.hiddenBrowsers.insert(browser.id) } else { config.hiddenBrowsers.remove(browser.id) }
        } else {
            if hidden { config.shownBrowsers.remove(browser.id) } else { config.shownBrowsers.insert(browser.id) }
        }
    }

    func makeDefaultBrowser() async {
        if let current = SystemDefaults.defaultBrowserBundleID, current != AppIdentity.bundleID {
            config.previousDefaultBrowser = current
        }
        do {
            try await SystemDefaults.makeDefaultBrowser()
        } catch {
            log.error("Couldn't become default browser: \(error)")
            SystemDefaults.openDefaultBrowserSettings()
        }
        refreshSystemState()
    }

    // MARK: - Rules

    func save(_ rule: Rule, kind: RuleKind) {
        var rules = config.rules(for: kind)
        if let index = rules.firstIndex(where: { $0.id == rule.id }) {
            rules[index] = rule
        } else {
            rules.append(rule)
        }
        config.setRules(rules, for: kind)
    }

    func deleteRule(id: Rule.ID, kind: RuleKind) {
        config.setRules(config.rules(for: kind).filter { $0.id != id }, for: kind)
    }

    func moveRules(kind: RuleKind, fromOffsets source: IndexSet, toOffset destination: Int) {
        var rules = config.rules(for: kind)
        rules.move(fromOffsets: source, toOffset: destination)
        config.setRules(rules, for: kind)
    }

    /// Called when the user ticks "Always open … here" in the picker. Goes to the top so it takes
    /// effect even if the picker was forced open past an existing rule.
    func remember(_ conditions: [Condition], action: RuleAction, kind: RuleKind) {
        var rules = config.rules(for: kind)
        if let index = rules.firstIndex(where: { $0.hasEquivalentConditions(to: conditions) }) {
            var existing = rules.remove(at: index)
            existing.action = action
            existing.isEnabled = true
            rules.insert(existing, at: 0)
        } else {
            rules.insert(Rule(conditions: conditions, action: action), at: 0)
        }
        config.setRules(rules, for: kind)
    }

    /// What would happen to this link, for the rule tester and the picker.
    func resolve(_ request: OpenRequest) -> (rule: Rule?, action: RuleAction) {
        switch request {
        case .link:
            let rule = RuleEngine.firstMatch(in: config.linkRules, for: request)
            return (rule, rule?.action ?? config.linkFallback)
        case .file:
            let rule = RuleEngine.firstMatch(in: config.fileRules, for: request)
            return (rule, rule?.action ?? .ask)
        }
    }

    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            log.error("Couldn't change login item: \(error)")
        }
        refreshSystemState()
    }

    // MARK: - File types

    func addFileType(_ type: UTType) async throws {
        guard !config.handledFileTypes.contains(where: { $0.identifier == type.identifier }) else {
            try await reclaimFileType(type.identifier)
            return
        }
        let previous = SystemDefaults.defaultApp(for: type)
            .flatMap { Bundle(url: $0)?.bundleIdentifier }
            .flatMap { $0 == AppIdentity.bundleID ? nil : $0 }
        try await SystemDefaults.setDefaultApp(Bundle.main.bundleURL, for: type)
        config.handledFileTypes.append(HandledFileType(identifier: type.identifier, previousHandlerBundleID: previous))
        refreshSystemState()
    }

    /// Hands the type back to the app that had it before.
    func removeFileType(_ identifier: String) async {
        guard let handled = config.handledFileTypes.first(where: { $0.identifier == identifier }) else { return }
        if let type = UTType(identifier), SystemDefaults.isDefaultHandler(for: identifier),
           let previous = handled.previousHandlerBundleID.flatMap(AppCatalog.info(bundleID:)) {
            do {
                try await SystemDefaults.setDefaultApp(previous.url, for: type)
            } catch {
                log.error("Couldn't restore \(previous.name) for \(identifier): \(error)")
            }
        }
        config.handledFileTypes.removeAll { $0.identifier == identifier }
        refreshSystemState()
    }

    /// Becomes the default again after another app took the type over.
    func reclaimFileType(_ identifier: String) async throws {
        guard let type = UTType(identifier) else { return }
        try await SystemDefaults.setDefaultApp(Bundle.main.bundleURL, for: type)
        refreshSystemState()
    }

    /// The app that should be listed first for a file: whatever used to be the default for its type.
    func preferredApp(for fileURL: URL) -> AppInfo? {
        if let contentType = try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType,
           let handled = config.handledFileTypes.first(where: { UTType($0.identifier).map(contentType.conforms(to:)) == true }),
           let app = handled.previousHandlerBundleID.flatMap(AppCatalog.info(bundleID:)) {
            return app
        }
        return AppCatalog.systemDefault(for: fileURL)
    }
}
