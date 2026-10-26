import AppKit
import PortreroCore

/// One entry in the picker: a browser, or one profile of a browser.
struct Browser: Identifiable {
    enum Engine {
        case chromium, firefox, other
    }

    struct Avatar {
        var image: NSImage?
        var color: NSColor
        var initial: String
    }

    let target: Target
    let appURL: URL
    let appName: String
    let profileName: String?
    let profileDetail: String?
    let engine: Engine
    let avatar: Avatar?
    /// False for apps that claim web links without being able to show web pages (e.g. ChatGPT).
    let isWebBrowser: Bool

    var id: String { target.key }
    var title: String { profileName ?? appName }
    var subtitle: String? { profileName == nil ? nil : appName }
    /// "Work — Google Chrome", for menus where there's no room for a subtitle.
    var fullTitle: String { subtitle.map { "\(title) — \($0)" } ?? title }
    var icon: NSImage { NSWorkspace.shared.icon(forFile: appURL.path(percentEncoded: false)) }
    var supportsPrivateWindows: Bool { engine != .other }
}

@MainActor
enum BrowserCatalog {
    /// Chromium browsers whose profiles live in Application Support/<path>/Local State.
    private static let chromiumDataPaths: [String: String] = [
        "com.google.Chrome": "Google/Chrome",
        "com.google.Chrome.beta": "Google/Chrome Beta",
        "com.google.Chrome.dev": "Google/Chrome Dev",
        "com.google.Chrome.canary": "Google/Chrome Canary",
        "org.chromium.Chromium": "Chromium",
        "com.microsoft.edgemac": "Microsoft Edge",
        "com.microsoft.edgemac.Beta": "Microsoft Edge Beta",
        "com.microsoft.edgemac.Dev": "Microsoft Edge Dev",
        "com.microsoft.edgemac.Canary": "Microsoft Edge Canary",
        "com.brave.Browser": "BraveSoftware/Brave-Browser",
        "com.brave.Browser.beta": "BraveSoftware/Brave-Browser-Beta",
        "com.brave.Browser.nightly": "BraveSoftware/Brave-Browser-Nightly",
        "com.vivaldi.Vivaldi": "Vivaldi",
    ]

    /// Firefox-family browsers whose profiles live in Application Support/<path>/profiles.ini.
    private static let firefoxDataPaths: [String: String] = [
        "org.mozilla.firefox": "Firefox",
        "org.mozilla.firefoxdeveloperedition": "Firefox",
        "org.mozilla.nightly": "Firefox",
        "app.zen-browser.zen": "zen",
        "io.gitlab.librewolf-community": "librewolf",
    ]

    /// `preferredBundleID` leads the list when Portrero itself is the default browser.
    static func discover(preferredBundleID: String? = nil) -> [Browser] {
        let probe = URL(string: "https://example.com")!
        let pageViewers = Set(NSWorkspace.shared.urlsForApplications(toOpen: .html).compactMap { Bundle(url: $0)?.bundleIdentifier })
        var seen = Set<String>()
        var browsers: [Browser] = []

        for appURL in AppCatalog.preferredOrder(NSWorkspace.shared.urlsForApplications(toOpen: probe)) {
            guard let bundleID = Bundle(url: appURL)?.bundleIdentifier,
                  bundleID != AppIdentity.bundleID,
                  seen.insert(bundleID).inserted
            else { continue }

            let appName = AppCatalog.displayName(of: appURL)
            let (engine, profiles, dataURL) = profiles(for: bundleID)
            let isWebBrowser = engine != .other || pageViewers.contains(bundleID)

            // A single profile isn't worth a separate entry; show the plain browser instead.
            guard profiles.count > 1 else {
                browsers.append(Browser(
                    target: Target(bundleID: bundleID), appURL: appURL, appName: appName,
                    profileName: nil, profileDetail: nil, engine: engine, avatar: nil, isWebBrowser: isWebBrowser
                ))
                continue
            }

            for profile in profiles {
                browsers.append(Browser(
                    target: Target(bundleID: bundleID, profile: profile.id), appURL: appURL, appName: appName,
                    profileName: profile.name, profileDetail: profile.detail, engine: engine,
                    avatar: avatar(for: profile, dataURL: dataURL), isWebBrowser: isWebBrowser
                ))
            }
        }

        // Default browser first, then real browsers alphabetically, then everything else;
        // profiles keep the browser's own order.
        let systemDefault = NSWorkspace.shared.urlForApplication(toOpen: probe).flatMap { Bundle(url: $0)?.bundleIdentifier }
        let defaultID = systemDefault == AppIdentity.bundleID ? preferredBundleID : systemDefault
        return browsers.enumerated().sorted { lhs, rhs in
            let (a, b) = (lhs.element, rhs.element)
            if a.target.bundleID == b.target.bundleID { return lhs.offset < rhs.offset }
            if a.target.bundleID == defaultID { return true }
            if b.target.bundleID == defaultID { return false }
            if a.isWebBrowser != b.isWebBrowser { return a.isWebBrowser }
            return a.appName.localizedStandardCompare(b.appName) == .orderedAscending
        }.map(\.element)
    }

    private static func profiles(for bundleID: String) -> (Browser.Engine, [BrowserProfile], URL?) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        if let path = chromiumDataPaths[bundleID] {
            let dataURL = support.appending(path: path)
            let data = try? Data(contentsOf: dataURL.appending(path: "Local State"))
            return (.chromium, data.map(ChromiumProfiles.parse(localState:)) ?? [], dataURL)
        }
        if let path = firefoxDataPaths[bundleID] {
            let ini = try? String(contentsOf: support.appending(path: "\(path)/profiles.ini"), encoding: .utf8)
            return (.firefox, ini.map(FirefoxProfiles.parse(profilesINI:)) ?? [], nil)
        }
        return (.other, [], nil)
    }

    private static func avatar(for profile: BrowserProfile, dataURL: URL?) -> Browser.Avatar {
        let image = profile.pictureFileName.flatMap { file in
            dataURL.flatMap { NSImage(contentsOf: $0.appending(path: profile.id).appending(path: file)) }
        }
        let color = profile.color.map(NSColor.init(argb:)) ?? fallbackColor(for: profile.name)
        let initial = profile.name.first(where: { $0.isLetter || $0.isNumber }).map { String($0).uppercased() } ?? "?"
        return Browser.Avatar(image: image, color: color, initial: initial)
    }

    private static func fallbackColor(for name: String) -> NSColor {
        let palette: [NSColor] = [.systemBlue, .systemPurple, .systemPink, .systemOrange, .systemGreen, .systemTeal, .systemIndigo]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

private extension NSColor {
    convenience init(argb: UInt32) {
        self.init(
            srgbRed: CGFloat((argb >> 16) & 0xFF) / 255,
            green: CGFloat((argb >> 8) & 0xFF) / 255,
            blue: CGFloat(argb & 0xFF) / 255,
            alpha: 1
        )
    }
}
