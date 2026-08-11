import XCTest
@testable import millio

final class AccountProductTransitionPresentationTests: XCTestCase {
    func testAvailableTargetsExcludeCurrentAndUnknownLegacy() {
        let targets = AccountProductTransitionSection.availableTargets(current: .bankAccount)

        XCTAssertFalse(targets.contains(.bankAccount))
        XCTAssertFalse(targets.contains(.unknownLegacy))
        XCTAssertTrue(targets.contains(.cash))
        XCTAssertTrue(targets.contains(.debitCard))
    }

    func testEveryKnownProductCanBeSelectedWhenCurrentTypeIsUnknown() {
        let targets = AccountProductTransitionSection.availableTargets(current: .unknownLegacy)

        XCTAssertEqual(targets.count, AccountProductType.allCases.count - 1)
        XCTAssertFalse(targets.contains(.unknownLegacy))
    }

    func testDepositTermsProduceValidMetadata() throws {
        let end = Date(timeIntervalSince1970: 2_000_000_000)

        let meta = try XCTUnwrap(AccountProductTransitionFormMapper.depositMetadata(
            rateText: "7,5",
            capitalization: .monthly,
            hasTerm: true,
            termEnd: end,
            allowsTopUp: true,
            allowsEarlyClose: true,
            penaltyPercentText: "25"
        ))

        XCTAssertEqual(meta.rate, Decimal(string: "7.5"))
        XCTAssertEqual(meta.termEnd, end)
        XCTAssertEqual(meta.earlyClosePenalty, Decimal(string: "0.25"))
        XCTAssertTrue(meta.remindEnd)
    }

    func testDepositTermsRejectMissingRateAndInvalidPenalty() {
        let arguments = (
            capitalization: AccountDepositCapitalization.monthly,
            hasTerm: false,
            termEnd: Date(),
            allowsTopUp: false,
            allowsEarlyClose: true
        )

        XCTAssertNil(AccountProductTransitionFormMapper.depositMetadata(
            rateText: "",
            capitalization: arguments.capitalization,
            hasTerm: arguments.hasTerm,
            termEnd: arguments.termEnd,
            allowsTopUp: arguments.allowsTopUp,
            allowsEarlyClose: arguments.allowsEarlyClose,
            penaltyPercentText: "25"
        ))
        XCTAssertNil(AccountProductTransitionFormMapper.depositMetadata(
            rateText: "7",
            capitalization: arguments.capitalization,
            hasTerm: arguments.hasTerm,
            termEnd: arguments.termEnd,
            allowsTopUp: arguments.allowsTopUp,
            allowsEarlyClose: arguments.allowsEarlyClose,
            penaltyPercentText: "101"
        ))
    }
}
