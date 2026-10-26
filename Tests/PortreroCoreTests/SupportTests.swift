import Foundation
import Testing
@testable import PortreroCore

@Suite struct TrackingParameters {
    @Test func stripsKnownTrackersAndKeepsTheRest() {
        let url = URL(string: "https://example.com/a?id=7&utm_source=x&UTM_Medium=y&fbclid=z&q=a%20b#top")!
        let cleaned = LinkCleaner.removingTrackingParameters(from: url)
        #expect(cleaned.absoluteString == "https://example.com/a?id=7&q=a%20b#top")
    }

    @Test func dropsTheQueryWhenNothingIsLeft() {
        let url = URL(string: "https://example.com/?gclid=1&utm_campaign=2")!
        #expect(LinkCleaner.removingTrackingParameters(from: url).absoluteString == "https://example.com/")
    }

    @Test func leavesCleanAndNonWebLinksUntouched() {
        let clean = URL(string: "https://example.com/?v=1&utm=keep")!
        #expect(LinkCleaner.removingTrackingParameters(from: clean) == clean)
        let mail = URL(string: "mailto:a@b.com?utm_source=x")!
        #expect(LinkCleaner.removingTrackingParameters(from: mail) == mail)
    }
}

@Suite struct ProfileParsing {
    @Test func chromiumLocalState() throws {
        let json = """
        {
          "profile": {
            "profiles_order": ["Profile 1", "Default"],
            "info_cache": {
              "Default": {
                "name": "Person 1", "is_using_default_name": true, "gaia_given_name": "Alex",
                "user_name": "me@example.com", "profile_highlight_color": -13952472,
                "gaia_picture_file_name": "Google Profile Picture.png"
              },
              "Profile 1": { "name": "Work", "is_using_default_name": false, "gaia_picture_file_name": "" },
              "Profile 9": { "name": "Ghost", "is_ephemeral": true },
              "Profile 3": { "name": "Archive" }
            }
          }
        }
        """
        let profiles = ChromiumProfiles.parse(localState: Data(json.utf8))
        #expect(profiles.map(\.id) == ["Profile 1", "Default", "Profile 3"])
        #expect(profiles.map(\.name) == ["Work", "Alex", "Archive"])
        #expect(profiles[1].detail == "me@example.com")
        #expect(profiles[1].color == UInt32(bitPattern: -13952472))
        #expect(profiles[1].pictureFileName == "Google Profile Picture.png")
        #expect(profiles[0].pictureFileName == nil)
    }

    @Test func chromiumGarbageYieldsNothing() {
        #expect(ChromiumProfiles.parse(localState: Data("not json".utf8)).isEmpty)
        #expect(ChromiumProfiles.parse(localState: Data("{}".utf8)).isEmpty)
    }

    @Test func firefoxProfilesINI() {
        let ini = """
        [Install4F96D1932A9F858E]
        Default=Profiles/def456.default-release
        Locked=1

        [Profile1]
        Name=work
        IsRelative=1
        Path=Profiles/abc123.work

        [Profile0]
        Name=default-release
        IsRelative=1
        Path=Profiles/def456.default-release

        [General]
        StartWithLastProfile=1
        """
        #expect(FirefoxProfiles.parse(profilesINI: ini).map(\.name) == ["default-release", "work"])
    }
}

@Suite struct ConfigCoding {
    @Test func roundTrips() throws {
        var config = Config()
        config.linkRules = [Rule(name: "GitHub", conditions: [Condition(.domain, .is, "github.com")],
                                 action: .open(Target(bundleID: "com.google.Chrome", profile: "Profile 1")))]
        config.linkFallback = .open(Target(bundleID: "com.apple.Safari"))
        config.hiddenBrowsers = ["org.mozilla.firefox"]
        config.handledFileTypes = [HandledFileType(identifier: "public.json", previousHandlerBundleID: "com.microsoft.VSCode")]

        let data = try JSONEncoder().encode(config)
        #expect(try JSONDecoder().decode(Config.self, from: data) == config)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"stripTrackingParameters": false}"#.utf8))
        #expect(config.stripTrackingParameters == false)
        #expect(config.showMenuBarIcon == true)
        #expect(config.linkFallback == .ask)
        #expect(config.linkRules.isEmpty)
    }

    @Test func unknownPlacementDoesNotBreakLoading() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data(#"{"pickerPlacement": "somewhere"}"#.utf8))
        #expect(config.pickerPlacement == .mousePointer)
    }

    @Test func targetKeys() {
        #expect(Target(bundleID: "a").key == "a")
        #expect(Target(bundleID: "a", profile: "Profile 1").key == "a#Profile 1")
    }
}
