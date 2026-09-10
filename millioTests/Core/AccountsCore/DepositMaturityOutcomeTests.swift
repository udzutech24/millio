import Foundation
import Testing
@testable import millio

@Suite("Deposit maturity outcome")
struct DepositMaturityOutcomeTests {
    private let accountID = UUID(uuidString: "99999999-8888-7777-6666-555555555555")!

    private func snapshot(
        currency: String = "RUB",
        currentBalance: DepositAmount = .confirmed(105_000),
        confirmedInterest: DepositAmount = .confirmed(5_000)
    ) -> DepositPresentationSnapshot {
        DepositPresentationSnapshot(
            asOf: Date(timeIntervalSince1970: 1_767_225_600), currency: currency,
            principal: .confirmed(100_000), confirmedInterest: confirmedInterest,
            estimatedDueInterest: .estimated(0), futureInterest: .estimated(0),
            currentBalance: currentBalance, projectedBalance: .estimated(105_000),
            availableToWithdraw: .unavailable, nextAccrual: nil,
            maturityDate: Date(timeIntervalSince1970: 1_767_225_600),
            maturityAmount: .estimated(105_000), daysRemaining: 0, progress: 1,
            lifecycleState: .maturedNeedsAction,
            capabilities: .init(
                allowsTopUp: false, allowsEarlyClose: false, allowsWithdrawal: false,
                reminderIsOperational: false, autoRolloverIsOperational: false
            ),
            unresolved: []
        )
    }

    private func allocation(tax: Decimal) -> DepositTaxAllocation {
        DepositTaxAllocation(
            accountID: accountID, grossInterestRUB: 5_000,
            allocatedExcessRUB: 5_000, allocatedTaxRUB: tax
        )
    }

    @Test("Рублёвый вклад: сумма, проценты, налог и остаток после налога")
    func rubleDepositSubtractsTax() throws {
        let outcome = try #require(
            DepositMaturityOutcome.make(snapshot: snapshot(), taxAllocation: allocation(tax: 650))
        )

        #expect(outcome.currency == "RUB")
        #expect(outcome.payoutAmount == 105_000)
        #expect(outcome.accruedInterest == 5_000)
        #expect(outcome.estimatedTaxRUB == 650)
        #expect(outcome.netPayout == 104_350)
    }

    @Test("Нет налоговой аллокации — нет ни налога, ни суммы после налога")
    func withoutAllocationTaxIsUnknown() throws {
        let outcome = try #require(DepositMaturityOutcome.make(snapshot: snapshot(), taxAllocation: nil))

        #expect(outcome.payoutAmount == 105_000)
        #expect(outcome.estimatedTaxRUB == nil)
        #expect(outcome.netPayout == nil)
    }

    @Test("Валютный вклад: рублёвый налог показываем, но из валютной суммы не вычитаем")
    func foreignCurrencyKeepsTaxSeparate() throws {
        let outcome = try #require(DepositMaturityOutcome.make(
            snapshot: snapshot(currency: "USD"), taxAllocation: allocation(tax: 650)
        ))

        #expect(outcome.estimatedTaxRUB == 650)
        #expect(outcome.netPayout == nil)
    }

    @Test("Баланс недоступен — итога нет, выдуманную сумму не показываем")
    func unavailableBalanceProducesNoOutcome() {
        #expect(DepositMaturityOutcome.make(
            snapshot: snapshot(currentBalance: .unavailable), taxAllocation: allocation(tax: 650)
        ) == nil)
    }

    @Test("Отрицательные проценты и налог не уводят витрину в минус")
    func negativeInputsAreClamped() throws {
        let outcome = try #require(DepositMaturityOutcome.make(
            snapshot: snapshot(confirmedInterest: .confirmed(-100)), taxAllocation: allocation(tax: -50)
        ))

        #expect(outcome.accruedInterest == 0)
        #expect(outcome.estimatedTaxRUB == 0)
        #expect(outcome.netPayout == 105_000)
    }

    @Test("Налог больше остатка — к получению ноль, а не отрицательная сумма")
    func taxLargerThanBalanceClampsToZero() throws {
        let outcome = try #require(DepositMaturityOutcome.make(
            snapshot: snapshot(currentBalance: .confirmed(400)), taxAllocation: allocation(tax: 650)
        ))

        #expect(outcome.netPayout == 0)
    }
}
