import Foundation

/// Constants shared by the Share Extension and the main Trinote app.
enum SharedImportConstants {
    /// From the TRINOTE_APP_GROUP build setting (via Info.plist), so forks signed with
    /// another team can use their own App Group.
    static let configuredAppGroupIdentifier =
        Bundle.main.object(forInfoDictionaryKey: "TrinoteAppGroup") as? String ?? "group.com.trinote"

    /// The App Group this install is actually entitled to. Sideloading tools (AltStore,
    /// SideStore, Sideloadly) re-sign with the user's team and rename the group, e.g.
    /// group.com.trinote → group.com.trinote.<TEAMID>, without touching Info.plist, so
    /// probe the likely names and use the first one iOS hands a container for.
    static let appGroupIdentifier: String = {
        appGroupCandidates().first {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        } ?? configuredAppGroupIdentifier
    }()

    static let hostURLScheme = "trinote"
    static let hostURLHost = "share-import"
    static let hostOpenURL = URL(string: "trinote://share-import")!

    static let metadataFileName = "pending-share-import.json"
    static let binaryFileName = "pending-share-import.bin"

    private static func appGroupCandidates() -> [String] {
        var candidates = [configuredAppGroupIdentifier]
        // AltStore and SideStore list the groups they assigned under this key.
        if let altGroups = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] {
            candidates += altGroups.filter { $0.hasPrefix(configuredAppGroupIdentifier) }
            candidates += altGroups.filter { !$0.hasPrefix(configuredAppGroupIdentifier) }
        }
        // Re-signed bundle IDs carry the same suffix as the group (com.trinote.<TEAMID> and
        // com.trinote.<TEAMID>.fileshare), so try group.<prefix> for each prefix, longest first.
        if let bundleID = Bundle.main.bundleIdentifier {
            let parts = bundleID.split(separator: ".")
            if parts.count >= 2 {
                for count in stride(from: parts.count, through: 2, by: -1) {
                    candidates.append("group." + parts.prefix(count).joined(separator: "."))
                }
            }
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }
}
