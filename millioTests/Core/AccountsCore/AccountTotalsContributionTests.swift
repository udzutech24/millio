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

    @Test("Кредитка без банка (kind == .cash) с лимитом — тоже входит как −долг (баг Ф7b-2)")
    func cashKindCreditCardIsTransformed() {
        // Форма «Новый продукт» кладёт кредитку без выбранного банка в .cash
        // (cardKind(bank: .other) == .cash). Знак ДОЛЖЕН применяться по наличию лимита.
        // Остаток 1 300 000, лимит 1 500 000 → долг 200 000.
        #expect(AccountTotalsContribution.signedValue(rawBalance: 1_300_000, kind: .cash, creditLimit: 1_500_000) == -200_000)
    }

    @Test("Знак — только для денежных card-kind: bankAccount/loan с лимитом не трогаем")
    func nonCardKindWithLimitUnchanged() {
        // Лимит проставляется ТОЛЬКО card-пресетом; на других kind это гипотетика, но
        // ограничение (.cash/.debitCard) защищает от случайного превращения в долг.
        #expect(AccountTotalsContribution.signedValue(rawBalance: 10_000, kind: .bankAccount, creditLimit: 5_000) == 10_000)
        #expect(AccountTotalsContribution.signedValue(rawBalance: 10_000, kind: .loan, creditLimit: 5_000) == 10_000)
    }
}
