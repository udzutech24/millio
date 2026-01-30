import Foundation
import Testing
@testable import millio

struct CurrencyRateServiceURLTests {
    @Test("CurrencyRateService builds latest URL for all sources")
    func testMakeLatestURL() {
        #expect(CurrencyRateService.makeLatestURL(for: .erapi) != nil)
        #expect(CurrencyRateService.makeLatestURL(for: .frankfurter) != nil)
    }
}

