import AppKit
import PortreroCore
import SwiftUI
import UniformTypeIdentifiers

struct FileTypesPane: View {
    @Environment(AppModel.self) private var model
    @State private var newExtension = ""
    @State private var error: String?

    private static let commonTypes: [(String, UTType)] = [
        ("JSON", .json),
        ("Markdown", UTType("net.daringfireball.markdown") ?? .plainText),
        ("YAML", .yaml),
        ("Plain Text", .plainText),
        ("CSV", .commaSeparatedText),
        ("XML", .xml),
        ("PDF", .pdf),
        ("SVG", .svg),
    ]

    var body: some View {
        Form {
            Section {
                if model.config.handledFileTypes.isEmpty {
                    Text("Portrero isn’t opening any file types yet. Add one below, then opening a file of that type in Finder shows the picker.")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                }
                ForEach(model.config.handledFileTypes) { handled in
                    FileTypeRow(
                        handled: handled,
                        isActive: model.activeFileTypes.contains(handled.identifier),
                        reclaim: { run { try await model.reclaimFileType(handled.identifier) } },
                        remove: { run { await model.removeFileType(handled.identifier) } }
                    )
                }
            } header: {
                Text("Opened by Portrero")
            } footer: {
                Text("Removing a type gives it back to the app that opened it before.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("Add a File Type") {
                HStack {
                    TextField("File extension", text: $newExtension, prompt: Text("json"))
                        .onSubmit(addExtension)
                    Button("Add", action: addExtension)
                        .disabled(FileMatcher.extensions(in: newExtension).isEmpty)
                }
                HStack {
                    Menu("Common Types") {
                        ForEach(Self.commonTypes, id: \.1.identifier) { name, type in
                            Button(name) { add(type) }
                                .disabled(model.config.handledFileTypes.contains { $0.identifier == type.identifier })
                        }
                    }
                    .fixedSize()
                    Button("Choose a File…", action: chooseFile)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: model.refreshSystemState)
        .alert("Couldn’t change the default app", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    private func addExtension() {
        for ext in FileMatcher.extensions(in: newExtension) {
            add(UTType(filenameExtension: ext) ?? .data)
        }
        newExtension = ""
    }

    private func add(_ type: UTType) {
        run { try await model.addFileType(type) }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Use Type"
        panel.message = "Choose a file. Portrero will open every file of the same type."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType { add(type) }
        }
    }

    private func run(_ work: @escaping @MainActor () async throws -> Void) {
        Task {
            do {
                try await work()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct FileTypeRow: View {
    let handled: HandledFileType
    let isActive: Bool
    let reclaim: () -> Void
    let remove: () -> Void

    var body: some View {
        let type = UTType(handled.identifier)

        HStack(spacing: 10) {
            Image(nsImage: type.map { NSWorkspace.shared.icon(for: $0) } ?? NSWorkspace.shared.icon(for: .data))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(type?.localizedDescription?.capitalizingFirstLetter ?? handled.identifier)
                Text(detail(for: type))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                Label("Another app took over", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Use Portrero", action: reclaim)
                    .controlSize(.small)
            }

            Button(action: remove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop opening these files with Portrero")
        }
        .padding(.vertical, 2)
    }

    @MainActor
    private func detail(for type: UTType?) -> String {
        var parts: [String] = []
        if let extensions = type?.tags[.filenameExtension], !extensions.isEmpty {
            parts.append(extensions.prefix(4).map { ".\($0)" }.joined(separator: ", "))
        }
        if let previous = handled.previousHandlerBundleID {
            parts.append("previously \(AppCatalog.name(forBundleID: previous))")
        }
        return parts.isEmpty ? handled.identifier : parts.joined(separator: " · ")
    }
}

private extension String {
    var capitalizingFirstLetter: String {
        prefix(1).uppercased() + dropFirst()
    }
}
