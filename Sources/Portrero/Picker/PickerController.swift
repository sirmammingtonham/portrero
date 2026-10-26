import AppKit
import Carbon.HIToolbox
import PortreroCore
import SwiftUI
import UniformTypeIdentifiers

/// Borderless floating panel that can take keyboard focus without activating Portrero, so the
/// app you clicked the link in stays frontmost if you cancel.
final class PickerPanel: NSPanel {
    init(contentView: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        self.contentView = contentView
        setContentSize(contentView.fittingSize)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PickerController {
    private let model: AppModel
    var openSettings: () -> Void = {}

    private var panel: PickerPanel?
    private var picker: PickerModel?
    private var queue: [PickerSubject] = []
    private var monitors: [Any] = []
    private var resignObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
    }

    /// Shows the picker, or queues the request if one is already on screen.
    func present(_ subject: PickerSubject) {
        guard panel == nil else {
            queue.append(subject)
            return
        }
        show(subject)
    }

    // MARK: - Showing

    private func show(_ subject: PickerSubject) {
        let items = makeItems(for: subject)
        guard !items.isEmpty else {
            presentNothingCanOpen(subject)
            return
        }

        let picker = PickerModel(subject: subject, items: items, scopes: RememberScope.scopes(for: subject))
        picker.onChoose = { [weak self] item in self?.choose(item) }
        picker.onChooseOtherApp = { [weak self] in self?.chooseOtherApp() }
        picker.onCopy = { [weak self] in self?.copySubject() }
        self.picker = picker

        let panel = PickerPanel(contentView: NSHostingView(rootView: PickerView(model: picker)))
        position(panel)
        self.panel = panel

        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        picker.shiftHeld = NSEvent.modifierFlags.contains(.shift)
        installMonitors(for: panel)
    }

    private func makeItems(for subject: PickerSubject) -> [PickerItem] {
        switch subject {
        case .link:
            return model.pickerBrowsers.map { PickerItem(destination: .browser($0)) }

        case .files(let urls, _):
            // Apps that can open every file; if none can, anything that opens at least one.
            let perFile = urls.map(AppCatalog.apps(toOpen:))
            var apps = perFile.dropFirst().reduce(perFile.first ?? []) { common, next in
                common.filter { app in next.contains { $0.id == app.id } }
            }
            if apps.isEmpty {
                var seen = Set<String>()
                apps = perFile.joined().filter { seen.insert($0.id).inserted }
            }

            // The app that used to be the default goes first.
            guard let preferred = urls.first.flatMap(model.preferredApp(for:)) else {
                return apps.map { PickerItem(destination: .app($0)) }
            }
            let rest = apps.filter { $0.id != preferred.id }.map { PickerItem(destination: .app($0)) }
            return [PickerItem(destination: .app(preferred), badge: "Default")] + rest
        }
    }

    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let margin: CGFloat = 8

        var origin: CGPoint
        switch model.config.pickerPlacement {
        case .mousePointer:
            // Pointer sits over the header, so the first browser is just below it.
            origin = CGPoint(x: mouse.x - 24, y: mouse.y + 14 - size.height)
        case .screenCenter:
            origin = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + visible.height * 0.58 - size.height / 2)
        }
        origin.x = min(max(origin.x, visible.minX + margin), visible.maxX - size.width - margin)
        origin.y = min(max(origin.y, visible.minY + margin), visible.maxY - size.height - margin)
        panel.setFrameOrigin(origin)
    }

    // MARK: - Choosing

    private func choose(_ item: PickerItem) {
        guard let picker else { return }
        let scope = picker.wantsRemember ? picker.selectedScope : nil
        let privateWindow = picker.wantsPrivateWindow

        switch (picker.subject, item.destination) {
        case (.link(let url, _), .browser(let browser)):
            dismiss()
            Launcher.open(url, in: browser, privateWindow: privateWindow && browser.supportsPrivateWindows)
            if let scope { model.remember(scope.conditions, action: .open(browser.target), kind: .link) }

        case (.files(let urls, _), .app(let app)):
            dismiss()
            Launcher.open(urls, withAppAt: app.url)
            if let scope, let bundleID = app.bundleID {
                model.remember(scope.conditions, action: .open(Target(bundleID: bundleID)), kind: .file)
            }

        default:
            dismiss()
        }
        showNext()
    }

    private func chooseOtherApp() {
        guard let picker, case .files(let urls, _) = picker.subject else { return }
        let scope = picker.wantsRemember ? picker.selectedScope : nil
        dismiss()

        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Open"
        panel.message = urls.count == 1
            ? "Choose an app to open “\(urls[0].lastPathComponent)”."
            : "Choose an app to open \(urls.count) files."
        NSApp.activate()
        if panel.runModal() == .OK, let appURL = panel.url {
            Launcher.open(urls, withAppAt: appURL)
            if let scope, let bundleID = Bundle(url: appURL)?.bundleIdentifier {
                model.remember(scope.conditions, action: .open(Target(bundleID: bundleID)), kind: .file)
            }
        }
        showNext()
    }

    private func copySubject() {
        guard let picker else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch picker.subject {
        case .link(let url, _):
            pasteboard.setString(url.absoluteString, forType: .string)
        case .files(let urls, _):
            pasteboard.writeObjects(urls as [NSURL])
        }
        cancel()
    }

    private func cancel(_ reason: StaticString = "cancelled") {
        log.debug("Picker closed: \(reason, privacy: .public)")
        dismiss()
        showNext()
        returnFocus()
    }

    /// Opening a link activates Portrero. If the picker closes without opening anything, give focus
    /// back to the app the link came from instead of leaving it with a windowless app.
    private func returnFocus() {
        guard panel == nil, NSApp.isActive,
              !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain })
        else { return }
        NSApp.hide(nil)
    }

    private func dismiss() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        panel?.orderOut(nil)
        panel = nil
        picker = nil
    }

    private func showNext() {
        guard panel == nil, !queue.isEmpty else { return }
        show(queue.removeFirst())
    }

    private func presentNothingCanOpen(_ subject: PickerSubject) {
        let alert = NSAlert()
        if subject.isLink {
            alert.messageText = "No browsers found"
            alert.informativeText = "Portrero couldn’t find a browser to open this link. Install one, or check Settings → Browsers."
        } else {
            alert.messageText = "No apps can open this file"
            alert.informativeText = "macOS doesn’t know of an app that opens this kind of file."
        }
        NSApp.activate()
        alert.runModal()
        showNext()
    }

    // MARK: - Keyboard & mouse

    private static let digitKeys: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9,
        kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2, kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5,
        kVK_ANSI_Keypad6: 6, kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9,
    ]

    private func installMonitors(for panel: PickerPanel) {
        let local = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged, .leftMouseDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
        // Clicking in any other app dismisses the picker, like a menu.
        let global = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel("click in another app") }
        }
        monitors = [local, global].compactMap { $0 }

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                // Menus (the "remember" scope menu) don't steal key status; anything else means the user moved on.
                guard let self, self.panel === panel else { return }
                self.cancel("panel resigned key")
            }
        }
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard let picker, let panel else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.type {
        case .flagsChanged:
            picker.shiftHeld = flags.contains(.shift)
            picker.commandHeld = flags.contains(.command)
            return false

        case .leftMouseDown:
            if event.window !== panel { cancel("click outside") }
            return false

        case .keyDown:
            let key = Int(event.keyCode)
            switch key {
            case kVK_Escape:
                cancel()
            case kVK_Return, kVK_ANSI_KeypadEnter:
                picker.chooseHighlighted()
            case kVK_DownArrow:
                picker.moveHighlight(by: 1)
            case kVK_UpArrow:
                picker.moveHighlight(by: -1)
            case kVK_Tab:
                picker.moveHighlight(by: flags.contains(.shift) ? -1 : 1)
            default:
                if let digit = Self.digitKeys[key] {
                    picker.choose(at: digit - 1)
                } else if flags.contains(.command), event.charactersIgnoringModifiers == "c" {
                    copySubject()
                } else if flags.contains(.command), event.charactersIgnoringModifiers == "," {
                    dismiss()
                    openSettings()
                    showNext()
                } else if flags.contains(.command), event.charactersIgnoringModifiers == "w" {
                    cancel()
                }
            }
            // Swallow everything else so stray keys don't beep or leak to other windows.
            return true

        default:
            return false
        }
    }

    #if DEBUG
    var debugState: [String: Any] {
        guard let panel, let picker else { return ["visible": false, "queued": queue.count] }
        return [
            "visible": true,
            "queued": queue.count,
            "isKeyWindow": panel.isKeyWindow,
            "frame": NSStringFromRect(panel.frame),
            "items": picker.items.map(\.title),
            "highlightedIndex": picker.highlightedIndex,
            "remember": picker.remember,
            "scope": picker.scopeID ?? NSNull(),
        ]
    }
    #endif
}
