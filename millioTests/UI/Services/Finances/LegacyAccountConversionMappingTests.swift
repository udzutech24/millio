import Foundation
import Testing
@testable import millio

/// Маппинг легаси-счёта в план создания core-двойника (Track C). Знаковый вклад ДОЛЖЕН совпадать
/// с `FinanceTotalsService.getAccountAmount`, иначе «Общий баланс» после конвертации разойдётся.
@Suite("LegacyAccountConversion mapping (Track C)")
@MainActor
struct LegacyAccountConversionMappingTests {

    // MARK: - Card

    @Test
    func debitCardMapsToDebitCardWithNetWorth() {
        let card = Card(name: "ОГ", cardNumber: "1234", cardType: .debit, balance: 150_000)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.kind == .debitCard)
        #expect(plan.openingBalance == Decimal(150_000))
        #expect(plan.currency == "RUB")
    }

    @Test
    func creditCardMapsToNegativeNetWorth() {
        // Кредитная карта: netWorth = −(лимит − доступно) = −(100000 − 30000) = −70000.
        let card = Card(name: "CC", cardNumber: "1", cardType: .credit, balance: 30_000, creditLimit: 100_000)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.kind == .debitCard)
        #expect(plan.openingBalance == Decimal(-70_000))
    }

    @Test
    func excludedCardContributesZero() {
        let card = Card(name: "X", cardNumber: "1", cardType: .debit, balance: 150_000, includeInTotal: false)
        let plan = LegacyAccountConversion.plan(for: card)
        #expect(plan.openingBalance == 0) // netWorthAmount == 0 при includeInTotal == false
    }

    // MARK: - Credit

    @Test
    func creditMapsToLoanMagnitude() {
        let credit = Credit(
            name: "Ипотека", amount: 500_000, interestRate: 9.5, monthlyPayment: 5_000,
            startDate: Date(), termMonths: 12, currency: "RUB"
        )
        let plan = LegacyAccountConversion.plan(for: credit)
        #expect(plan.kind == .loan)
        // opening = магнитуда remainingAmount (движок C инвертирует → баланс −500000 = −remainingAmount).
        #expect(plan.openingBalance == Decimal(500_000))
    }

    // MARK: - Investment

    @Test
    func positiveInvestmentMapsToManualAsset() {
        let inv = Investment(name: "Квартира", investmentType: .positive, category: .house, amount: 20_000_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.kind == .manualAsset)
        #expect(plan.openingBalance == Decimal(20_000_000))
    }

    @Test
    func negativeInvestmentIsNegative() {
        let inv = Investment(name: "Минус", investmentType: .negative, category: .other, amount: 5_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.openingBalance == Decimal(-5_000))
    }

    @Test
    func excludedInvestmentContributesZero() {
        let inv = Investment(name: "Excl", investmentType: .positive, category: .other, amount: 5_000, includeInTotal: false)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "RUB")
        #expect(plan.openingBalance == 0)
    }

    @Test
    func marketInvestmentStillMapsToManualAsset() {
        // Осознанная девиация: даже акции/крипта → .manualAsset (рыночный движок игнорировал бы opening).
        let inv = Investment(name: "AAPL", investmentType: .positive, category: .stocks, amount: 45_000)
        let plan = LegacyAccountConversion.plan(for: inv, currency: "USD")
        #expect(plan.kind == .manualAsset)
        #expect(plan.openingBalance == Decimal(45_000))
        #expect(plan.currency == "USD")
    }
}
