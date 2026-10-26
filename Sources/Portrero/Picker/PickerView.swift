import AppKit
import SwiftUI

struct PickerView: View {
    @Bindable var model: PickerModel

    static let width: CGFloat = 340
    static let rowHeight: CGFloat = 44
    private static let maxVisibleRows = 8

    var body: some View {
        VStack(spacing: 0) {
            PickerHeader(subject: model.subject, onCopy: model.onCopy)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().padding(.horizontal, 12)

            list

            Divider().padding(.horizontal, 12)

            footer
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
        }
        .frame(width: Self.width)
        .pickerBackground()
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(model.items.enumerated()), id: \.element.id) { index, item in
                        PickerRow(
                            item: item,
                            shortcut: index < 9 ? index + 1 : nil,
                            isHighlighted: index == model.highlightedIndex,
                            showsPrivate: model.wantsPrivateWindow
                        )
                        .id(index)
                        .contentShape(Rectangle())
                        .onHover { if $0 { model.highlightedIndex = index } }
                        .onTapGesture { model.choose(at: index) }
                    }
                }
                .padding(6)
            }
            .scrollDisabled(model.items.count <= Self.maxVisibleRows)
            .scrollIndicators(.never)
            .frame(height: listHeight)
            .onChange(of: model.highlightedIndex) { _, index in
                proxy.scrollTo(index)
            }
        }
    }

    private var listHeight: CGFloat {
        let rows = CGFloat(max(1, min(model.items.count, Self.maxVisibleRows)))
        let peek: CGFloat = model.items.count > Self.maxVisibleRows ? Self.rowHeight / 2 : 0
        return rows * Self.rowHeight + (rows - 1) * 2 + 12 + peek
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 6) {
            if let scope = model.selectedScope {
                Toggle(isOn: rememberBinding) { Text("Always open") }
                    .toggleStyle(.checkbox)
                    .fixedSize()

                if model.scopes.count > 1 {
                    Menu {
                        Picker("Scope", selection: $model.scopeID) {
                            ForEach(model.scopes) { Text($0.title).tag(Optional($0.id)) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: {
                        Text(scope.title)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                } else {
                    Text(scope.title).fontWeight(.medium).lineLimit(1)
                }
                Text("here").lineLimit(1)
            }

            Spacer(minLength: 8)

            if model.subject.isLink {
                KeyHint(key: "⇧", label: "Private", isActive: model.shiftHeld)
            } else {
                Button("Other…", action: model.onChooseOtherApp)
                    .buttonStyle(.borderless)
                    .help("Choose any app to open this with")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
    }

    private var rememberBinding: Binding<Bool> {
        Binding(get: { model.remember || model.commandHeld }, set: { model.remember = $0 })
    }
}

private struct PickerHeader: View {
    let subject: PickerSubject
    let onCopy: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            leadingIcon
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
            Button(action: onCopy) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help(subject.isLink ? "Copy link (⌘C)" : "Copy path (⌘C)")
        }
    }

    @ViewBuilder
    private var leadingIcon: some View {
        switch subject {
        case .link(_, let source):
            if let source, let app = AppCatalog.info(bundleID: source) {
                AppIcon(image: app.icon, size: 26).help("From \(app.name)")
            } else {
                Image(systemName: "link")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(Color.accentColor.gradient))
                    .frame(width: 26, height: 26)
            }
        case .files(let urls, _):
            let paths = urls.map { $0.path(percentEncoded: false) }
            AppIcon(image: NSWorkspace.shared.icon(forFiles: paths) ?? NSWorkspace.shared.icon(for: .data), size: 28)
        }
    }

    private var title: String {
        switch subject {
        case .link(let url, _):
            url.host(percentEncoded: false) ?? url.absoluteString
        case .files(let urls, _):
            urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        }
    }

    private var detail: String {
        switch subject {
        case .link(let url, _):
            var rest = url.absoluteString
            if let scheme = rest.range(of: "://") { rest = String(rest[scheme.upperBound...]) }
            if let host = url.host(percentEncoded: false), rest.hasPrefix(host) { rest.removeFirst(host.count) }
            return rest.isEmpty || rest == "/" ? url.absoluteString : rest
        case .files(let urls, _):
            let folder = urls[0].deletingLastPathComponent().path(percentEncoded: false)
            return (folder as NSString).abbreviatingWithTildeInPath
        }
    }
}

private struct PickerRow: View {
    let item: PickerItem
    let shortcut: Int?
    let isHighlighted: Bool
    let showsPrivate: Bool

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    if showsPrivate && item.supportsPrivateWindows {
                        Text("Private")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(isHighlighted ? .white.opacity(0.25) : .primary.opacity(0.1)))
                    }
                }
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut {
                Keycap(text: "\(shortcut)", onAccent: isHighlighted)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: PickerView.rowHeight)
        .foregroundStyle(isHighlighted ? .white : .primary)
        .opacity(showsPrivate && !item.supportsPrivateWindows ? 0.45 : 1)
        .background {
            if isHighlighted {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor)
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch item.destination {
        case .browser(let browser): BrowserIcon(browser: browser, size: 30)
        case .app(let app): AppIcon(image: app.icon, size: 30)
        }
    }
}

struct Keycap: View {
    let text: String
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(onAccent ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(onAccent ? AnyShapeStyle(.white.opacity(0.22)) : AnyShapeStyle(.quaternary))
            )
    }
}

private struct KeyHint: View {
    let key: String
    let label: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            Keycap(text: key, onAccent: false)
            Text(label)
        }
        .foregroundStyle(isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
        .help("Hold ⇧ while choosing to open a private window")
    }
}

private extension View {
    /// Liquid Glass on macOS 26, a popover-style material before that.
    @ViewBuilder
    func pickerBackground() -> some View {
        if #available(macOS 26, *) {
            self
                .glassEffect(.regular, in: .rect(cornerRadius: 18, style: .continuous))
        } else {
            self
                .background(VisualEffectBackground(material: .popover))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                )
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}
