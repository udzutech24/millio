import Foundation
import Testing
@testable import millio

struct AppStoreReviewLinkTests {
    @Test("App Store review URL uses provided app id")
    func makeReviewURLUsesProvidedID() {
        let url = AppStoreReviewLink.makeReviewURL(appStoreID: "6757660504")
        #expect(url?.absoluteString == "itms-apps://apps.apple.com/app/id6757660504?action=write-review")
    }

    @Test("App Store review URL trims surrounding whitespace")
    func makeReviewURLTrimsWhitespace() {
        let url = AppStoreReviewLink.makeReviewURL(appStoreID: "  6757660504  ")
        #expect(url?.absoluteString == "itms-apps://apps.apple.com/app/id6757660504?action=write-review")
    }

    @Test("App Store review URL is nil for empty id")
    func makeReviewURLEmptyIDIsNil() {
        let url = AppStoreReviewLink.makeReviewURL(appStoreID: "   ")
        #expect(url == nil)
    }
}
