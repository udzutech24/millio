//
//  FinanceOverviewLedgerModelsTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import Testing
@testable import millio

struct FinanceOverviewLedgerModelsTests {
    @Test("Ledger builder считает saldo и сортирует группы по сумме")
    func ledgerBuilderBuildsDebitCreditSides() {
        let presentation = FinanceOverviewLedgerBuilder.makePresentation(
            items: [
                .init(groupID: "inventory", groupName: "Склад", groupColorHex: "#FFDD00", accountID: "a1", accountName: "Склад ФФ", accountIcon: "shippingbox.fill", customIconName: nil, customIconColor: nil, amount: 2_518_023, side: .debit),
                .init(groupID: "debtors", groupName: "Дебиторы", groupColorHex: "#7AD7FF", accountID: "a2", accountName: "WB", accountIcon: "person.2.fill", customIconName: nil, customIconColor: nil, amount: 2_059_702, side: .debit),
                .init(groupID: "inventory", groupName: "Склад", groupColorHex: "#FFDD00", accountID: "a3", accountName: "Склад МП ВБ", accountIcon: "shippingbox.fill", customIconName: nil, customIconColor: nil, amount: 3_579_015, side: .debit),
                .init(groupID: "loan", groupName: "Денежный кредит", groupColorHex: "#FF6B6B", accountID: "c1", accountName: "Банк", accountIcon: "banknote.fill", customIconName: nil, customIconColor: nil, amount: 16_657_223, side: .credit)
            ]
        )

        #expect(abs(presentation.debit.total - 8_156_740) < 0.01)
        #expect(abs(presentation.credit.total - 16_657_223) < 0.01)
        #expect(abs(presentation.saldo + 8_500_483) < 0.01)
        #expect(presentation.debit.accountCount == 3)
        #expect(presentation.credit.accountCount == 1)
        #expect(presentation.debit.groups.map(\.name) == ["Склад", "Дебиторы"])
        #expect(presentation.debit.groups.first?.accounts.map(\.name) == ["Склад МП ВБ", "Склад ФФ"])
    }

    @Test("Ledger builder отбрасывает нулевые суммы")
    func ledgerBuilderIgnoresZeroBalances() {
        let presentation = FinanceOverviewLedgerBuilder.makePresentation(
            items: [
                .init(groupID: "cash", groupName: "Счета", groupColorHex: nil, accountID: "1", accountName: "Касса", accountIcon: "creditcard.fill", customIconName: nil, customIconColor: nil, amount: 0, side: .debit),
                .init(groupID: "loan", groupName: "Кредит", groupColorHex: nil, accountID: "2", accountName: "Банк", accountIcon: "banknote.fill", customIconName: nil, customIconColor: nil, amount: 4_000, side: .credit)
            ]
        )

        #expect(presentation.debit.groups.isEmpty)
        #expect(presentation.credit.groups.count == 1)
        #expect(abs(presentation.credit.total - 4_000) < 0.01)
    }

    @Test("Ledger interaction раскрывает только одну сторону за раз")
    func ledgerInteractionTogglesSingleExpandedSide() {
        let openDebit = FinanceOverviewLedgerInteraction.toggledExpandedSide(
            current: nil,
            tapped: .debit
        )
        let switchToCredit = FinanceOverviewLedgerInteraction.toggledExpandedSide(
            current: openDebit,
            tapped: .credit
        )
        let collapseCredit = FinanceOverviewLedgerInteraction.toggledExpandedSide(
            current: switchToCredit,
            tapped: .credit
        )

        #expect(openDebit == .debit)
        #expect(switchToCredit == .credit)
        #expect(collapseCredit == nil)
    }

    @Test("Ledger presentation возвращает выбранную сторону")
    func ledgerPresentationReturnsSelectedSide() {
        let presentation = FinanceOverviewLedgerBuilder.makePresentation(
            items: [
                .init(groupID: "cash", groupName: "Счета", groupColorHex: nil, accountID: "1", accountName: "Касса", accountIcon: "creditcard.fill", customIconName: nil, customIconColor: nil, amount: 12_000, side: .debit),
                .init(groupID: "loan", groupName: "Кредит", groupColorHex: nil, accountID: "2", accountName: "Банк", accountIcon: "banknote.fill", customIconName: nil, customIconColor: nil, amount: 4_000, side: .credit)
            ]
        )

        #expect(presentation.sidePresentation(for: .debit).side == .debit)
        #expect(presentation.sidePresentation(for: .credit).side == .credit)
        #expect(abs(presentation.sidePresentation(for: .debit).total - 12_000) < 0.01)
        #expect(abs(presentation.sidePresentation(for: .credit).total - 4_000) < 0.01)
    }
}
