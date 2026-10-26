import AppKit
import PortreroCore

/// Decides what happens to every link and file macOS hands to Portrero.
@MainActor
final class Router {
    private let model: AppModel
    private let picker: PickerController

    init(model: AppModel, picker: PickerController) {
        self.model = model
        self.picker = picker
    }

    func handle(_ urls: [URL], sourceBundleID: String?) {
        // ⌥ held while clicking a link means "let me choose this time", even if a rule matches.
        let forcePicker = NSEvent.modifierFlags.contains(.option)
        let files = urls.filter(\.isFileURL)
        log.debug("Asked to open \(urls.count) item(s) from \(sourceBundleID ?? "unknown", privacy: .public)")

        for url in urls where !url.isFileURL {
            route(link: url, source: sourceBundleID, forcePicker: forcePicker)
        }
        if !files.isEmpty {
            route(files: files, source: sourceBundleID, forcePicker: forcePicker)
        }
    }

    private func route(link url: URL, source: String?, forcePicker: Bool) {
        let url = model.config.stripTrackingParameters ? LinkCleaner.removingTrackingParameters(from: url) : url
        let request = OpenRequest.link(url, sourceBundleID: source)

        if !forcePicker, let target = model.resolve(request).action.target, let browser = model.browser(for: target) {
            Launcher.open(url, in: browser)
        } else {
            picker.present(.link(url, sourceBundleID: source))
        }
    }

    private func route(files: [URL], source: String?, forcePicker: Bool) {
        var byApp: [URL: [URL]] = [:]
        var undecided: [URL] = []

        for file in files {
            let request = OpenRequest.file(file, sourceBundleID: source)
            if !forcePicker,
               let target = model.resolve(request).action.target,
               let app = AppCatalog.info(bundleID: target.bundleID) {
                byApp[app.url, default: []].append(file)
            } else {
                undecided.append(file)
            }
        }

        for (appURL, files) in byApp {
            Launcher.open(files, withAppAt: appURL)
        }
        if !undecided.isEmpty {
            picker.present(.files(undecided, sourceBundleID: source))
        }
    }
}
