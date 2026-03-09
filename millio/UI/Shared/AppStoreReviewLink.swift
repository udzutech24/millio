import Foundation

enum AppStoreReviewLink {
    static var url: URL? {
        guard
            let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String,
            !appStoreID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }

        return URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)?action=write-review")
    }
}

