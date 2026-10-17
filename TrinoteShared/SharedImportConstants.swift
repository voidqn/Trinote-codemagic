import Foundation

/// Constants shared by the Share Extension and the main Trinote app.
enum SharedImportConstants {
    /// From the TRINOTE_APP_GROUP build setting (via Info.plist), so forks signed with
    /// another team can use their own App Group.
    static let appGroupIdentifier =
        Bundle.main.object(forInfoDictionaryKey: "TrinoteAppGroup") as? String ?? "group.com.trinote"
    static let hostURLScheme = "trinote"
    static let hostURLHost = "share-import"
    static let hostOpenURL = URL(string: "trinote://share-import")!

    static let metadataFileName = "pending-share-import.json"
    static let binaryFileName = "pending-share-import.bin"
}
