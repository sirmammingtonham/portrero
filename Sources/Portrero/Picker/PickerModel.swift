import AppKit
import Observation
import PortreroCore

enum PickerSubject {
    case link(URL, sourceBundleID: String?)
    case files([URL], sourceBundleID: String?)

    var isLink: Bool {
        if case .link = self { return true }
        return false
    }

    var sourceBundleID: String? {
        switch self {
        case .link(_, let source), .files(_, let source): source
        }
    }
}

struct PickerItem: Identifiable {
    enum Destination {
        case browser(Browser)
        case app(AppInfo)
    }

    let destination: Destination
    /// e.g. "Default" for the app that used to own a file type.
    var badge: String?

    var id: String {
        switch destination {
        case .browser(let browser): "browser:\(browser.id)"
        case .app(let app): "app:\(app.id)"
        }
    }

    var title: String {
        switch destination {
        case .browser(let browser): browser.title
        case .app(let app): app.name
        }
    }

    var subtitle: String? {
        switch destination {
        case .browser(let browser): browser.subtitle
        case .app: badge
        }
    }

    var supportsPrivateWindows: Bool {
        if case .browser(let browser) = destination { return browser.supportsPrivateWindows }
        return false
    }
}

/// One way to turn a picker choice into a rule, e.g. "github.com" or ".json files in Projects".
struct RememberScope: Identifiable, Hashable {
    let id: String
    let title: String
    let conditions: [Condition]

    @MainActor
    static func scopes(for subject: PickerSubject) -> [RememberScope] {
        var scopes: [RememberScope] = []
        switch subject {
        case .link(let url, let source):
            if let host = DomainMatcher.host(of: url) {
                scopes.append(RememberScope(id: "domain", title: host, conditions: [Condition(.domain, .is, host)]))
            }
            if let source {
                scopes.append(RememberScope(
                    id: "source", title: "links from \(AppCatalog.name(forBundleID: source))",
                    conditions: [Condition(.sourceApp, .is, source)]
                ))
            }

        case .files(let urls, _):
            let extensions = Set(urls.map { $0.pathExtension.lowercased() })
            let folders = Set(urls.map { $0.deletingLastPathComponent().path(percentEncoded: false) })
            let ext = extensions.count == 1 ? extensions.first.flatMap { $0.isEmpty ? nil : $0 } : nil
            let folder = folders.count == 1 ? folders.first : nil
            let folderName = folder.map { FileManager.default.displayName(atPath: $0) }

            if let ext {
                scopes.append(RememberScope(id: "ext", title: ".\(ext) files", conditions: [Condition(.fileExtension, .is, ext)]))
            }
            if let ext, let folder, let folderName {
                scopes.append(RememberScope(
                    id: "extFolder", title: ".\(ext) files in \(folderName)",
                    conditions: [Condition(.fileExtension, .is, ext), Condition(.folder, .isInside, folder)]
                ))
            }
            if let folder, let folderName {
                scopes.append(RememberScope(id: "folder", title: "files in \(folderName)", conditions: [Condition(.folder, .isInside, folder)]))
            }
        }
        return scopes
    }
}

@MainActor
@Observable
final class PickerModel {
    let subject: PickerSubject
    let items: [PickerItem]
    let scopes: [RememberScope]

    var highlightedIndex = 0
    var remember = false
    var scopeID: String?
    var shiftHeld = false
    var commandHeld = false

    @ObservationIgnored var onChoose: (PickerItem) -> Void = { _ in }
    @ObservationIgnored var onChooseOtherApp: () -> Void = {}
    @ObservationIgnored var onCopy: () -> Void = {}

    init(subject: PickerSubject, items: [PickerItem], scopes: [RememberScope]) {
        self.subject = subject
        self.items = items
        self.scopes = scopes
        self.scopeID = scopes.first?.id
    }

    /// Holding ⌘ while choosing remembers the choice without touching the checkbox.
    var wantsRemember: Bool { (remember || commandHeld) && selectedScope != nil }
    var wantsPrivateWindow: Bool { shiftHeld && subject.isLink }
    var selectedScope: RememberScope? { scopes.first { $0.id == scopeID } }

    func moveHighlight(by delta: Int) {
        guard !items.isEmpty else { return }
        highlightedIndex = (highlightedIndex + delta + items.count) % items.count
    }

    func chooseHighlighted() {
        choose(at: highlightedIndex)
    }

    func choose(at index: Int) {
        guard items.indices.contains(index) else { return }
        onChoose(items[index])
    }
}
