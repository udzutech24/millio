import Foundation

enum AppStoreReviewLink {
    // Keep rating flow working even if Info.plist key is missing in a build config.
    static let fallbackAppStoreID = "6757660504"

    static var url: URL? {
        let configuredID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String
        let appStoreID = normalizedAppStoreID(from: configuredID) ?? fallbackAppStoreID
        return makeReviewURL(appStoreID: appStoreID)
    }

    static func makeReviewURL(appStoreID: String) -> URL? {
        guard let normalizedID = normalizedAppStoreID(from: appStoreID) else {
            return nil
        }
        return URL(string: "itms-apps://apps.apple.com/app/id\(normalizedID)?action=write-review")
    }

    private static func normalizedAppStoreID(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
