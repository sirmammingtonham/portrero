import AppKit

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    struct Actions {
        var openSettings: () -> Void
        var openClipboardLink: (URL) -> Void
    }

    private static let autosaveName = "Portrero"

    private let model: AppModel
    private let actions: Actions
    private var item: NSStatusItem?
    private var occlusionObserver: NSObjectProtocol?

    init(model: AppModel, actions: Actions) {
        self.model = model
        self.actions = actions
    }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            item = makeItem()
        }
        // Hiding (rather than removing) the item keeps the spot the user ⌘-dragged it to.
        item?.isVisible = visible
        updateOcclusion()
    }

    private func makeItem() -> NSStatusItem {
        // New items go to the far left of the status area, which on a full menu bar is under the
        // camera notch. Until the user moves it, start just left of the system's own items instead.
        // (Positions are measured in points from the right edge of the screen.)
        let positionKey = "NSStatusItem Preferred Position \(Self.autosaveName)"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(420, forKey: positionKey)
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.autosaveName = Self.autosaveName
        item.button?.image = NSImage(systemSymbolName: "arrow.triangle.branch", accessibilityDescription: "Portrero")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: item.button?.window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateOcclusion() }
        }
        return item
    }

    /// Lets Settings explain a missing icon: a crowded menu bar puts it under the notch, where it can't be seen.
    private func updateOcclusion() {
        guard let item, item.isVisible, let window = item.button?.window else {
            model.menuBarIconIsHidden = false
            return
        }
        model.menuBarIconIsHidden = !window.occlusionState.contains(.visible)
    }

    // Built on open so the default-browser status and clipboard item are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        model.refreshSystemState()
        menu.removeAllItems()

        if model.isDefaultBrowser {
            let status = menu.addItem(withTitle: "Portrero is your default browser", action: nil, keyEquivalent: "")
            status.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(paletteColors: [.systemGreen]))
            status.isEnabled = false
        } else {
            menu.addItem(item("Make Portrero Your Default Browser…", #selector(makeDefault)))
        }
        menu.addItem(.separator())

        let clipboard = item("Open Link from Clipboard", #selector(openClipboard))
        clipboard.isEnabled = clipboardURL != nil
        if let url = clipboardURL { clipboard.toolTip = url.absoluteString }
        menu.addItem(clipboard)

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit Portrero", #selector(quit), key: "q"))
    }

    private var clipboardURL: URL? {
        guard let string = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host() != nil
        else { return nil }
        return url
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func makeDefault() {
        Task { await model.makeDefaultBrowser() }
    }

    @objc private func openClipboard() {
        if let clipboardURL { actions.openClipboardLink(clipboardURL) }
    }

    @objc private func openSettings() {
        actions.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
