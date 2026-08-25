import XCTest
@testable import millio

final class AccountProductTransitionPresentationTests: XCTestCase {
    func testAvailableTargetsExcludeCurrentAndUnknownLegacy() {
        let targets = AccountProductTransitionPresentation.availableTargets(current: .bankAccount)

        XCTAssertFalse(targets.contains(.bankAccount))
        XCTAssertFalse(targets.contains(.unknownLegacy))
        XCTAssertTrue(targets.contains(.cash))
        XCTAssertTrue(targets.contains(.debitCard))
    }

    func testEveryKnownProductCanBeSelectedWhenCurrentTypeIsUnknown() {
        let targets = AccountProductTransitionPresentation.availableTargets(current: .unknownLegacy)

        XCTAssertEqual(targets.count, AccountProductType.allCases.count - 1)
        XCTAssertFalse(targets.contains(.unknownLegacy))
    }

    func testRussianTitlesMatchCreateFlowAndHaveNoDuplicates() {
        let locale = Locale(identifier: "ru")
        let targets = AccountProductTransitionPresentation.availableTargets(current: .unknownLegacy)
        let titles = targets.map {
            AccountProductTransitionPresentation.title(for: $0, locale: locale)
        }

        XCTAssertEqual(Set(titles).count, titles.count)
        XCTAssertEqual(
            AccountProductTransitionPresentation.title(for: .bankAccount, locale: locale),
            FinanceAddAccountProductOption.account.title(locale: locale)
        )
        XCTAssertEqual(
            AccountProductTransitionPresentation.title(for: .loan, locale: locale),
            FinanceAddAccountProductOption.credit.title(locale: locale)
        )
        XCTAssertEqual(
            AccountProductTransitionPresentation.title(for: .realEstate, locale: locale),
            FinanceAddAccountProductOption.house.title(locale: locale)
        )
        XCTAssertTrue(
            AccountProductTransitionPresentation.title(for: .creditCard, locale: locale)
                .hasPrefix(FinanceAddAccountProductOption.card.title(locale: locale))
        )
        XCTAssertTrue(
            AccountProductTransitionPresentation.title(for: .payable, locale: locale)
                .hasPrefix(FinanceAddAccountProductOption.debt.title(locale: locale))
        )
    }

    func testTitlesHaveNoDuplicatesInEverySupportedLanguage() {
        let targets = AccountProductTransitionPresentation.availableTargets(current: .unknownLegacy)
        let languages = Language.allCases.filter { $0 != .system }

        for language in languages {
            let locale = Locale(identifier: language.rawValue)
            let titles = targets.map {
                AccountProductTransitionPresentation.title(for: $0, locale: locale)
            }

            XCTAssertEqual(
                Set(titles).count,
                titles.count,
                "Duplicate transition title for locale \(language.rawValue): \(titles)"
            )
        }
    }

    func testTransitionLabelsClearlySeparateCurrentAndNewTypes() {
        let expectations: [(String, String, String, String)] = [
            ("en", "Current type", "New type", "Change type"),
            ("ru", "Текущий тип", "Новый тип", "Изменить тип"),
            ("zh-Hans", "当前类型", "新类型", "更改类型")
        ]

        for (language, current, target, action) in expectations {
            let locale = Locale(identifier: language)
            XCTAssertEqual(AppLocalization.string("accounts_core.transition.current", locale: locale), current)
            XCTAssertEqual(AppLocalization.string("accounts_core.transition.target", locale: locale), target)
            XCTAssertEqual(AppLocalization.string("accounts_core.transition.correct", locale: locale), action)
        }
    }

    func testDepositTermsProduceValidMetadata() throws {
        let end = Date(timeIntervalSince1970: 2_000_000_000)

        let meta = try XCTUnwrap(AccountProductTransitionFormMapper.depositMetadata(
            rateText: "7,5",
            capitalization: .monthly,
            payoutDay: 15,
            hasTerm: true,
            termEnd: end,
            allowsTopUp: true,
            allowsEarlyClose: true,
            penaltyPercentText: "25"
        ))

        XCTAssertEqual(meta.rate, Decimal(string: "7.5"))
        XCTAssertEqual(meta.payoutDay, 15)
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

    func testDepositTermsAcceptZeroPenaltyAndKeepPayoutDay() throws {
        let meta = try XCTUnwrap(AccountProductTransitionFormMapper.depositMetadata(
            rateText: "7",
            capitalization: .quarterly,
            payoutDay: 31,
            hasTerm: false,
            termEnd: Date(),
            allowsTopUp: false,
            allowsEarlyClose: true,
            penaltyPercentText: "0"
        ))

        XCTAssertEqual(meta.earlyClosePenalty, 0)
        XCTAssertEqual(meta.payoutDay, 31)
    }
}
