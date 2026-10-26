import PortreroCore
import SwiftUI

struct GeneralPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                DefaultBrowserStatus()
            }

            Section {
                Picker("When no rule matches", selection: $model.config.linkFallback) {
                    Text("Ask Me").tag(RuleAction.ask)
                    Divider()
                    ForEach(model.orderedBrowsers) { browser in
                        Label {
                            Text(browser.fullTitle)
                        } icon: {
                            Image(nsImage: MenuIcons.browser(browser))
                        }
                        .tag(RuleAction.open(browser.target))
                    }
                    if let target = model.config.linkFallback.target, model.browser(for: target) == nil {
                        Text("Missing Browser").tag(model.config.linkFallback)
                    }
                }

                Toggle(isOn: $model.config.stripTrackingParameters) {
                    Text("Remove tracking parameters")
                    Text("Strips utm_source, fbclid, gclid and similar from links before opening them.")
                }
            } header: {
                Text("Links")
            }

            Section("Picker") {
                Picker("Show the picker", selection: $model.config.pickerPlacement) {
                    Text("At the Mouse Pointer").tag(PickerPlacement.mousePointer)
                    Text("In the Center of the Screen").tag(PickerPlacement.screenCenter)
                }
                ShortcutRow(label: "Choose a browser or app", keys: ["1", "–", "9"], or: "↩")
                ShortcutRow(label: "Open in a private window", keys: ["⇧"], suffix: "while choosing")
                ShortcutRow(label: "Remember the choice", keys: ["⌘"], suffix: "while choosing")
                ShortcutRow(label: "Ask even when a rule matches", keys: ["⌥"], suffix: "while clicking a link")
            }

            Section {
                Toggle("Open at login", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                Toggle(isOn: $model.config.showMenuBarIcon) {
                    Text("Show in menu bar")
                    if !model.config.showMenuBarIcon {
                        Text("Open Portrero from your Applications folder to get back to these settings.")
                    } else if model.menuBarIconIsHidden {
                        Text("Your menu bar is full, so the icon is hidden behind the camera. Hold ⌘ and drag other icons out of the menu bar to make room.")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct DefaultBrowserStatus: View {
    @Environment(AppModel.self) private var model
    @State private var isWorking = false

    var body: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                Text(model.isDefaultBrowser ? "Portrero is your default browser" : "Portrero isn’t your default browser")
                    .font(.headline)
                Text(model.isDefaultBrowser
                     ? "Links you open outside a browser come here first, then go wherever your rules say."
                     : "Make it the default so it can send each link to the right browser and profile.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if model.isDefaultBrowser {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                    .accessibilityLabel("Default browser")
            } else {
                Button("Make Default") {
                    isWorking = true
                    Task {
                        await model.makeDefaultBrowser()
                        isWorking = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isWorking)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutRow: View {
    let label: String
    let keys: [String]
    var or: String?
    var suffix: String?

    var body: some View {
        LabeledContent(label) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { key in
                    if key == "–" { Text(key).foregroundStyle(.secondary) } else { Keycap(text: key) }
                }
                if let or {
                    Text("or").foregroundStyle(.secondary)
                    Keycap(text: or)
                }
                if let suffix {
                    Text(suffix).foregroundStyle(.secondary)
                }
            }
        }
    }
}
