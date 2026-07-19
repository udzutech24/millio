import Foundation
import Testing
@testable import millio

/// Ф7b: единая точка знакового вклада счёта в сальдо. Кредитная карта входит как −долг,
/// всё остальное (в т.ч. дебетовые карты без лимита) — бит-в-бит прежним значением.
@Suite("AccountTotalsContribution (Ф7b)")
struct AccountTotalsContributionTests {

    @Test("Кредитная карта: вклад = остаток − лимит = −долг")
    func creditCardContributesNegativeDebt() {
        // Остаток лимита 1 374 000, лимит 1 500 000 → долг 126 000.
        let value = AccountTotalsContribution.signedValue(
            rawBalance: 1_374_000, kind: .debitCard, creditLimit: 1_500_000
        )
        #expect(value == -126_000)
    }

    @Test("Полностью погашенная кредитка (остаток == лимит) даёт вклад 0, не положительный")
    func fullyPaidCreditCardContributesZero() {
        let value = AccountTotalsContribution.signedValue(
            rawBalance: 1_500_000, kind: .debitCard, creditLimit: 1_500_000
        )
        #expect(value == 0)
    }

    @Test("Дебетовая карта (creditLimit == nil) — значение не меняется")
    func debitCardUnchanged() {
        let value = AccountTotalsContribution.signedValue(
            rawBalance: 42_000, kind: .debitCard, creditLimit: nil
        )
        #expect(value == 42_000)
    }

    @Test("Знак применяется ТОЛЬКО к .debitCard: cash/bankAccount с лимитом не трогаем")
    func onlyDebitCardKindIsTransformed() {
        // Гипотетический счёт другого kind с проставленным лимитом не должен превращаться в долг —
        // условие ключуется строго на .debitCard (пресет «Карта»), см. дизайн Ф7b.
        #expect(AccountTotalsContribution.signedValue(rawBalance: 10_000, kind: .cash, creditLimit: 5_000) == 10_000)
        #expect(AccountTotalsContribution.signedValue(rawBalance: 10_000, kind: .bankAccount, creditLimit: 5_000) == 10_000)
        #expect(AccountTotalsContribution.signedValue(rawBalance: 10_000, kind: .loan, creditLimit: 5_000) == 10_000)
    }
}
