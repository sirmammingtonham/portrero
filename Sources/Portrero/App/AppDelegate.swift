import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private lazy var picker = PickerController(model: model)
    private lazy var router = Router(model: model, picker: picker)
    private lazy var settings = SettingsWindowController(model: model)
    private lazy var statusItem = StatusItemController(model: model, actions: .init(
        openSettings: { [weak self] in self?.settings.show() },
        openClipboardLink: { [weak self] url in self?.router.handle([url], sourceBundleID: nil) }
    ))

    // Links and files that launched the app arrive before didFinishLaunching, so set up here.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.make()
        model.refresh()
        picker.openSettings = { [weak self] in self?.settings.show() }
        #if DEBUG
        DebugHooks.install(picker: picker) { [weak self] pane in self?.settings.show(pane: pane) }
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        syncMenuBarIcon()
        if !model.config.hasCompletedOnboarding {
            model.config.hasCompletedOnboarding = true
            settings.show(pane: .general)
        }
        // Browsers get installed and profiles get added; pick that up whenever the user comes back.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refresh() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        router.handle(urls, sourceBundleID: AppleEventSource.currentSenderBundleID())
    }

    /// Launching Portrero again (Finder, Spotlight, Dock) opens settings — the way back in when the menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settings.show()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// App menu → Settings… (reaches the delegate through the responder chain).
    @objc func showSettings(_ sender: Any?) {
        settings.show()
    }

    private func syncMenuBarIcon() {
        withObservationTracking {
            statusItem.setVisible(model.config.showMenuBarIcon)
        } onChange: { [weak self] in
            Task { @MainActor in self?.syncMenuBarIcon() }
        }
    }
}

enum AppleEventSource {
    /// Bundle ID of the app that asked macOS to open the current URL or file (e.g. Slack, Mail, Finder).
    @MainActor
    static func currentSenderBundleID() -> String? {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let descriptor = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))
        else { return nil }
        let pid = pid_t(descriptor.int32Value)
        guard pid > 0, pid != ProcessInfo.processInfo.processIdentifier else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }
}
