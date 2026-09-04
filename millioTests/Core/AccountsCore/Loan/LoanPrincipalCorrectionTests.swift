import Foundation
import SwiftData
import Testing
@testable import millio

/// Правка суммы кредита и остаток долга (спека Р6): сумма живёт в договоре, остаток — в ленте.
///
/// Развилка одна: пока по договору не было платежей, других причин для расхождения нет, и правка
/// суммы догоняет ленту. После первого платежа остаток — результат операций, и форма его не трогает.
@Suite(.serialized)
@MainActor
struct LoanPrincipalCorrectionTests {

    private func makeLoan(context: ModelContext, openingBalance: Decimal) throws -> Account {
        try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: openingBalance
        )
    }

    private func outstanding(of account: Account) -> Decimal {
        LoanOutstanding.fromLedger(
            balance: AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: Date())
        )
    }

    @Test("Платежей не было: увеличенная сумма кредита становится остатком долга")
    func alignsOutstandingUpWhenNoPaymentsMade() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let account = try makeLoan(context: container.mainContext, openingBalance: 1_200_000)

        let event = try LoanPrincipalCorrection(modelContext: container.mainContext)
            .alignOutstanding(account: account, to: 1_500_000, paymentsMade: 0)

        #expect(event?.type == .expense)
        #expect(outstanding(of: account) == 1_500_000)
    }

    @Test("Платежей не было: уменьшенная сумма кредита тоже становится остатком долга")
    func alignsOutstandingDownWhenNoPaymentsMade() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let account = try makeLoan(context: container.mainContext, openingBalance: 1_200_000)

        let event = try LoanPrincipalCorrection(modelContext: container.mainContext)
            .alignOutstanding(account: account, to: 900_000, paymentsMade: 0)

        #expect(event?.type == .income)
        #expect(outstanding(of: account) == 900_000)
    }

    @Test("Платежи уже вносились: остаток остаётся за лентой")
    func keepsLedgerOutstandingAfterFirstPayment() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let account = try makeLoan(context: container.mainContext, openingBalance: 1_200_000)
        let eventsBefore = account.events?.count ?? 0

        let event = try LoanPrincipalCorrection(modelContext: container.mainContext)
            .alignOutstanding(account: account, to: 5_000_000, paymentsMade: 3)

        #expect(event == nil)
        #expect(outstanding(of: account) == 1_200_000)
        #expect(account.events?.count == eventsBefore)
    }

    @Test("Сумма не изменилась — корректирующего события нет")
    func noEventWhenNothingToAlign() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let account = try makeLoan(context: container.mainContext, openingBalance: 1_200_000)
        let eventsBefore = account.events?.count ?? 0

        let event = try LoanPrincipalCorrection(modelContext: container.mainContext)
            .alignOutstanding(account: account, to: 1_200_000, paymentsMade: 0)

        #expect(event == nil)
        #expect(account.events?.count == eventsBefore)
    }

    @Test("Не кредит — операция отбивается, а не пишет мусор в чужую ленту")
    func rejectsNonLoanAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let account = try AccountsCoreService(modelContext: container.mainContext).createAccount(
            name: "Карта",
            kind: .debitCard,
            currency: "RUB",
            openingBalance: 10_000
        )

        #expect(throws: LoanPaymentError.self) {
            try LoanPrincipalCorrection(modelContext: container.mainContext)
                .alignOutstanding(account: account, to: 50_000, paymentsMade: 0)
        }
    }
}
