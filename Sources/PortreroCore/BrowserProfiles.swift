import Foundation

public struct BrowserProfile: Hashable, Sendable {
    /// What the browser needs to open this profile: Chromium's directory name or Firefox's profile name.
    public var id: String
    public var name: String
    /// Usually the signed-in account's email.
    public var detail: String?
    /// Chromium's profile highlight colour, ARGB.
    public var color: UInt32?
    /// Avatar image file name inside the profile directory.
    public var pictureFileName: String?

    public init(id: String, name: String, detail: String? = nil, color: UInt32? = nil, pictureFileName: String? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.color = color
        self.pictureFileName = pictureFileName
    }
}

/// Reads profiles from a Chromium browser's `Local State` file (Chrome, Edge, Brave, Vivaldi, …).
public enum ChromiumProfiles {
    public static func parse(localState data: Data) -> [BrowserProfile] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = root["profile"] as? [String: Any],
              let cache = profile["info_cache"] as? [String: Any]
        else { return [] }

        var profiles: [BrowserProfile] = []
        for (directory, value) in cache {
            guard let info = value as? [String: Any] else { continue }
            if info["is_ephemeral"] as? Bool == true || info["is_omitted_from_profile_list"] as? Bool == true {
                continue
            }

            var name = nonEmpty(info["name"]) ?? directory
            // Chrome shows the account's name for profiles the user never renamed ("Person 1").
            if info["is_using_default_name"] as? Bool == true,
               let accountName = nonEmpty(info["gaia_given_name"]) ?? nonEmpty(info["gaia_name"]) {
                name = accountName
            }

            profiles.append(BrowserProfile(
                id: directory,
                name: name,
                detail: nonEmpty(info["user_name"]),
                color: (info["profile_highlight_color"] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.int64Value) },
                pictureFileName: nonEmpty(info["gaia_picture_file_name"])
            ))
        }

        let order = profile["profiles_order"] as? [String] ?? []
        let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return profiles.sorted {
            let (a, b) = (rank[$0.id] ?? .max, rank[$1.id] ?? .max)
            return a != b ? a < b : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

/// Reads profiles from a Firefox-family `profiles.ini`.
public enum FirefoxProfiles {
    public static func parse(profilesINI text: String) -> [BrowserProfile] {
        var sections: [(name: String, values: [String: String])] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                sections.append((String(line.dropFirst().dropLast()), [:]))
            } else if let equals = line.firstIndex(of: "="), !sections.isEmpty {
                let key = line[..<equals].trimmingCharacters(in: .whitespaces)
                let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
                sections[sections.count - 1].values[key] = value
            }
        }

        // Modern Firefox records the default per installation in [Install…] sections.
        let installDefaults = Set(sections.filter { $0.name.hasPrefix("Install") }.compactMap { $0.values["Default"] })

        let profiles = sections
            .filter { $0.name.hasPrefix("Profile") }
            .compactMap { section -> (BrowserProfile, isDefault: Bool)? in
                guard let name = section.values["Name"], !name.isEmpty else { return nil }
                let isDefault = section.values["Path"].map(installDefaults.contains) == true
                    || section.values["Default"] == "1"
                return (BrowserProfile(id: name, name: name), isDefault)
            }

        return profiles.filter(\.isDefault).map(\.0) + profiles.filter { !$0.isDefault }.map(\.0)
    }
}
