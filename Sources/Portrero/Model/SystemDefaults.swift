import AppKit
import UniformTypeIdentifiers

/// Reads and changes which apps macOS uses for web links and file types.
@MainActor
enum SystemDefaults {
    private static let webProbe = URL(string: "https://example.com")!

    static var isDefaultBrowser: Bool {
        defaultBrowserBundleID == AppIdentity.bundleID
    }

    /// macOS asks the user to confirm this change.
    static var defaultBrowserBundleID: String? {
        NSWorkspace.shared.urlForApplication(toOpen: webProbe).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }

    static func makeDefaultBrowser() async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
        // Setting http normally covers https too; make sure.
        if !isDefaultBrowser {
            try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "https")
        }
    }

    static func openDefaultBrowserSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
    }

    static func defaultApp(for type: UTType) -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: type)
    }

    static func isDefaultHandler(for typeIdentifier: String) -> Bool {
        guard let type = UTType(typeIdentifier), let url = defaultApp(for: type) else { return false }
        return Bundle(url: url)?.bundleIdentifier == AppIdentity.bundleID
    }

    static func setDefaultApp(_ appURL: URL, for type: UTType) async throws {
        try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
    }
}
