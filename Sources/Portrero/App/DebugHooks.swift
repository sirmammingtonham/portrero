#if DEBUG
import AppKit
import Carbon.HIToolbox
import ScreenCaptureKit

/// Debug builds only: lets scripts drive the UI and inspect its state.
///
///   swift scripts/debug.swift pane browsers        show a settings pane
///   swift scripts/debug.swift link https://…       show the picker for a link
///   swift scripts/debug.swift state /tmp/state     write window/focus/picker state as JSON
///   swift scripts/debug.swift key down             press a key in the key window (down, up, return,
///                                                  esc, tab, 1–5, cmd-c, cmd-comma)
///   swift scripts/debug.swift shot /tmp/x.png      screenshot the picker or settings window
@MainActor
enum DebugHooks {
    static func install(picker: PickerController,
                        showPane: @escaping @MainActor @Sendable (SettingsPane) -> Void) {
        observe("pane") { value in
            SettingsPane(rawValue: value).map(showPane)
        }
        observe("link") { value in
            URL(string: value).map { picker.present(.link($0, sourceBundleID: nil)) }
        }
        observe("state") { value in
            writeState(picker: picker, to: URL(fileURLWithPath: value))
        }
        observe("key") { value in
            press(value)
        }
        observe("shot") { value in
            Task { await screenshot(to: URL(fileURLWithPath: value)) }
        }
    }

    private static func observe(_ command: String, _ action: @escaping @MainActor (String) -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: .init("app.portrero.debug.\(command)"), object: nil, queue: .main
        ) { note in
            let value = (note.object as? String) ?? ""
            MainActor.assumeIsolated { action(value) }
        }
    }

    // MARK: - State

    private static func writeState(picker: PickerController, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state: [String: Any] = [
            "appIsActive": NSApp.isActive,
            "frontmostApp": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? NSNull(),
            "activationPolicy": NSApp.activationPolicy().rawValue,
            "keyWindow": NSApp.keyWindow.map { String(describing: type(of: $0)) } ?? NSNull(),
            "windows": NSApp.windows.filter(\.isVisible).map { window in
                [
                    "class": String(describing: type(of: window)),
                    "title": window.title,
                    "isKey": window.isKeyWindow,
                    "frame": NSStringFromRect(window.frame),
                    "toolbar": window.toolbar.map { toolbar in
                        ["identifier": toolbar.identifier, "isVisible": toolbar.isVisible,
                         "items": toolbar.items.map(\.itemIdentifier.rawValue)] as [String: Any]
                    } ?? NSNull(),
                    "occluded": !window.occlusionState.contains(.visible),
                ] as [String: Any]
            },
            "picker": picker.debugState,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: directory.appending(path: "state.json"))
        }
    }

    // MARK: - Screenshots

    /// Captures the picker (or the settings window) over the desktop picture. Only Portrero's own
    /// windows are captured: a full-screen window showing the desktop picture covers everything
    /// else (so glass has nothing else to blur), and the capture filter includes just that window
    /// and the target. Uses the macOS 14.4+ own-process capture, so no Screen Recording permission.
    private static func screenshot(to url: URL) async {
        guard #available(macOS 14.4, *) else { return }
        let target = NSApp.windows.first { $0 is PickerPanel && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible && $0.styleMask.contains(.titled) }
        guard let target, let screen = target.screen,
              let wallpaper = NSWorkspace.shared.desktopImageURL(for: screen).flatMap(NSImage.init(contentsOf:))
        else { return }

        let backdrop = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.level = .screenSaver
        backdrop.contentView?.wantsLayer = true
        backdrop.contentView?.layer?.contents = wallpaper
        backdrop.contentView?.layer?.contentsGravity = .resizeAspectFill
        let level = target.level
        target.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        backdrop.orderFrontRegardless()
        defer {
            backdrop.orderOut(nil)
            target.level = level
        }
        try? await Task.sleep(for: .milliseconds(600))

        do {
            let content = try await SCShareableContent.currentProcess
            let ids = [backdrop.windowNumber, target.windowNumber].map(CGWindowID.init)
            let windows = content.windows.filter { ids.contains($0.windowID) }
            guard windows.count == 2,
                  let screenID = screen.deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID,
                  let display = content.displays.first(where: { $0.displayID == screenID })
            else { return }

            // Display-local, top-left-origin points, with a margin of desktop around the window.
            let margin: CGFloat = 56
            let frame = target.frame.insetBy(dx: -margin, dy: -margin).intersection(screen.frame)
            let config = SCStreamConfiguration()
            config.sourceRect = CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY,
                                       width: frame.width, height: frame.height)
            config.width = Int(frame.width * screen.backingScaleFactor)
            config.height = Int(frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.ignoreShadowsDisplay = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(display: display, including: windows), configuration: config)
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            NSLog("Screenshot failed: \(error)")
        }
    }

    // MARK: - Synthetic keys

    private static let keys: [String: (code: Int, chars: String, flags: NSEvent.ModifierFlags)] = [
        "down": (kVK_DownArrow, "\u{F701}", []), "up": (kVK_UpArrow, "\u{F700}", []),
        "return": (kVK_Return, "\r", []), "esc": (kVK_Escape, "\u{1B}", []), "tab": (kVK_Tab, "\t", []),
        "cmd-c": (kVK_ANSI_C, "c", .command), "cmd-comma": (kVK_ANSI_Comma, ",", .command),
        "1": (kVK_ANSI_1, "1", []), "2": (kVK_ANSI_2, "2", []), "3": (kVK_ANSI_3, "3", []),
        "4": (kVK_ANSI_4, "4", []), "5": (kVK_ANSI_5, "5", []),
    ]

    /// Posts into Portrero's own event queue, so it exercises the same monitors a real key press hits.
    private static func press(_ name: String) {
        guard let key = keys[name], let window = NSApp.keyWindow else { return }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: key.flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: key.chars,
                charactersIgnoringModifiers: key.chars, isARepeat: false, keyCode: UInt16(key.code))
            event.map { NSApp.postEvent($0, atStart: false) }
        }
    }
}
#endif
