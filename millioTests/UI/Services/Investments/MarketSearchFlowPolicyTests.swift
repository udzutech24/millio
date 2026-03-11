import XCTest
@testable import millio

final class MarketSearchFlowPolicyTests: XCTestCase {
    func testAutoOpenSearchWhenSwitchingFromNonMarketToStocksWithoutSymbol() {
        XCTAssertTrue(
            MarketSearchFlowPolicy.shouldAutoOpenSearch(
                previousCategory: .other,
                newCategory: .stocks,
                marketSymbol: "",
                isEditingLockedIdentity: false
            )
        )
    }

    func testDoesNotAutoOpenWhenSymbolAlreadyExists() {
        XCTAssertFalse(
            MarketSearchFlowPolicy.shouldAutoOpenSearch(
                previousCategory: .other,
                newCategory: .crypto,
                marketSymbol: "BTCUSD",
                isEditingLockedIdentity: false
            )
        )
    }

    func testDoesNotAutoOpenForLockedEditingIdentity() {
        XCTAssertFalse(
            MarketSearchFlowPolicy.shouldAutoOpenSearch(
                previousCategory: .other,
                newCategory: .stocks,
                marketSymbol: "",
                isEditingLockedIdentity: true
            )
        )
    }

    func testDoesNotAutoOpenWhenAlreadyInMarketCategory() {
        XCTAssertFalse(
            MarketSearchFlowPolicy.shouldAutoOpenSearch(
                previousCategory: .stocks,
                newCategory: .crypto,
                marketSymbol: "",
                isEditingLockedIdentity: false
            )
        )
    }
}
