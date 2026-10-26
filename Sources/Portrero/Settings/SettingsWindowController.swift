import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class SettingsNavigation {
    var pane: SettingsPane = .general {
        didSet {
            guard pane != oldValue, !isTraversingHistory else { return }
            backStack.append(oldValue)
            forwardStack.removeAll()
        }
    }
    private(set) var backStack: [SettingsPane] = []
    private(set) var forwardStack: [SettingsPane] = []
    @ObservationIgnored private var isTraversingHistory = false

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(pane)
        traverse(to: previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(pane)
        traverse(to: next)
    }

    private func traverse(to pane: SettingsPane) {
        isTraversingHistory = true
        self.pane = pane
        isTraversingHistory = false
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let navigation = SettingsNavigation()
    private var window: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func show(pane: SettingsPane? = nil) {
        if let pane { navigation.pane = pane }
        let window = window ?? makeWindow()
        self.window = window

        // A Dock icon and app menu while settings are open; back to menu-bar-only when closed.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        model.refresh()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(navigation: navigation).environment(model))
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.setContentSize(NSSize(width: 800, height: 560))
        window.center()
        window.setFrameAutosaveName("PortreroSettings")
        syncTitle(of: window)
        return window
    }

    /// Like System Settings, the toolbar shows the selected pane. (`navigationTitle` only reaches
    /// windows that SwiftUI itself owns.)
    private func syncTitle(of window: NSWindow) {
        window.title = withObservationTracking {
            navigation.pane.title
        } onChange: { [weak self, weak window] in
            Task { @MainActor in window.map { self?.syncTitle(of: $0) } }
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        model.refreshSystemState()
    }
}
