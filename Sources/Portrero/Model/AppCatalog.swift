import AppKit
import UniformTypeIdentifiers

/// An app that can open a file.
struct AppInfo: Identifiable, Hashable {
    let url: URL
    let bundleID: String?
    let name: String

    var id: String { bundleID ?? url.path(percentEncoded: false) }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)) }
}

enum AppIdentity {
    static let bundleID = Bundle.main.bundleIdentifier ?? "app.portrero.Portrero"
}

@MainActor
enum AppCatalog {
    static func info(at url: URL) -> AppInfo? {
        guard url.pathExtension == "app" else { return nil }
        return AppInfo(url: url, bundleID: Bundle(url: url)?.bundleIdentifier, name: displayName(of: url))
    }

    static func info(bundleID: String) -> AppInfo? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).flatMap(info(at:))
    }

    static func name(forBundleID bundleID: String) -> String {
        info(bundleID: bundleID)?.name ?? bundleID
    }

    static func displayName(of appURL: URL) -> String {
        let name = FileManager.default.displayName(atPath: appURL.path(percentEncoded: false))
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Apps that can open this file, excluding Portrero, de-duplicated, sorted by name.
    static func apps(toOpen fileURL: URL) -> [AppInfo] {
        unique(NSWorkspace.shared.urlsForApplications(toOpen: fileURL))
    }

    static func apps(toOpen type: UTType) -> [AppInfo] {
        unique(NSWorkspace.shared.urlsForApplications(toOpen: type))
    }

    /// The system's default app for a file, unless that's Portrero itself.
    static func systemDefault(for fileURL: URL) -> AppInfo? {
        NSWorkspace.shared.urlForApplication(toOpen: fileURL).flatMap(info(at:)).flatMap {
            $0.bundleID == AppIdentity.bundleID ? nil : $0
        }
    }

    /// Regular apps that are running now — handy suggestions for "Source app is …".
    static func runningApps() -> [AppInfo] {
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != AppIdentity.bundleID }
            .compactMap { $0.bundleURL.flatMap(info(at:)) }
        return Array(Set(apps)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Prefers copies in /Applications over ones buried in other bundles (e.g. inside Xcode).
    static func preferredOrder(_ urls: [URL]) -> [URL] {
        urls
            .filter { !$0.path(percentEncoded: false).contains(".app/Contents/") }
            .sorted { rank($0) < rank($1) }
    }

    private static func rank(_ url: URL) -> Int {
        let path = url.path(percentEncoded: false)
        if path.hasPrefix("/Applications/") || path.hasPrefix("/System/Applications/") { return 0 }
        if path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications").path) { return 1 }
        return 2
    }

    private static func unique(_ urls: [URL]) -> [AppInfo] {
        var seen = Set<String>()
        return preferredOrder(urls)
            .compactMap(info(at:))
            .filter { $0.bundleID != AppIdentity.bundleID && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
