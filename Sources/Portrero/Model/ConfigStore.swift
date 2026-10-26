import Foundation
import PortreroCore

/// Persists `Config` as JSON in ~/Library/Application Support/Portrero/config.json.
struct ConfigStore {
    let fileURL: URL

    init(fileURL: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appending(path: "Portrero/config.json")) {
        self.fileURL = fileURL
    }

    func load() -> Config {
        guard let data = try? Data(contentsOf: fileURL) else { return Config() }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            // Keep the unreadable file around rather than silently overwriting someone's rules.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            log.error("Couldn't read config, starting fresh (backup at \(backup.path)): \(error)")
            return Config()
        }
    }

    func save(_ config: Config) {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: fileURL, options: .atomic)
        } catch {
            log.error("Couldn't save config: \(error)")
        }
    }
}
