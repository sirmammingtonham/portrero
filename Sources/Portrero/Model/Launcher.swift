import AppKit

@MainActor
enum Launcher {
    static func open(_ url: URL, in browser: Browser, privateWindow: Bool = false) {
        var arguments: [String] = []
        switch browser.engine {
        case .chromium:
            if let profile = browser.target.profile { arguments.append("--profile-directory=\(profile)") }
            if privateWindow { arguments.append("--incognito") }
        case .firefox:
            if let profile = browser.target.profile { arguments += ["-P", profile] }
            if privateWindow { arguments.append("-private-window") }
        case .other:
            break
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        guard !arguments.isEmpty else {
            NSWorkspace.shared.open([url], withApplicationAt: browser.appURL, configuration: configuration) { _, error in
                if let error { log.error("Couldn't open \(url) in \(browser.appName): \(error)") }
            }
            return
        }

        // Arguments are ignored by an already-running app, so launch a fresh instance. Chromium and
        // Firefox hand the arguments to the running instance and exit straight away (like `open -na`).
        configuration.createsNewApplicationInstance = true
        configuration.arguments = arguments + [url.absoluteString]
        NSWorkspace.shared.openApplication(at: browser.appURL, configuration: configuration) { _, error in
            if let error { log.error("Couldn't open \(url) in \(browser.fullTitle): \(error)") }
        }
    }

    static func open(_ files: [URL], withAppAt appURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(files, withApplicationAt: appURL, configuration: configuration) { _, error in
            if let error { log.error("Couldn't open \(files.count) file(s) with \(appURL.lastPathComponent): \(error)") }
        }
    }
}
