import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф4 кредита: плановый платёж уменьшает ТОЛЬКО тело долга.
///
/// Главный инвариант экрана: проценты — плата за пользование деньгами, остаток по ним не падает
/// (спека Р6). Если бы платёж уменьшал долг на всю сумму, net worth рос бы на величину процентов,
/// которых пользователь никогда не увидит обратно.
@Suite(.serialized)
@MainActor
struct LoanPaymentRecorderTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func makeLoan(context: ModelContext) throws -> Account {
        try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 1_200_000, rate: 18.9, monthlyPayment: nil, paymentDay: 15,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ),
            date: calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
        )
    }

    private func balance(_ account: Account, on date: Date) -> Decimal {
        AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: date)
    }

    @Test("Платёж уменьшает долг ровно на тело и не трогает проценты")
    func paymentReducesPrincipalOnly() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let paymentDate = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!

        let before = balance(account, on: paymentDate)
        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: account, principalPart: 13_151, interestPart: 17_912, date: paymentDate
        )
        let after = balance(account, on: paymentDate)

        // Долг хранится отрицательным балансом: платёж двигает его ВВЕРХ ровно на тело.
        #expect(after - before == 13_151)
        #expect(after == -1_186_849)
    }

    @Test("Проценты платежа копятся в договоре, а не в балансе")
    func interestGoesToContractOnly() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let store = LoanContractStore(context: context)
        try store.upsert(accountID: account.id) {
            $0.principal = 1_200_000
            $0.annualRatePercent = 18.9
            $0.termPeriods = 60
            $0.paidInterestTotal = 74_642
            $0.paymentsMade = 4
        }
        try context.save()

        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: account, principalPart: 13_151, interestPart: 17_912,
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!
        )

        let contract = try #require(try store.contract(for: account.id))
        #expect(contract.paymentsMade == 5)
        #expect(contract.paidInterestTotal == 92_554)
    }

    @Test("Договора ещё нет: платёж заводит его и считает первым")
    func paymentCreatesContractWhenMissing() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)

        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: account, principalPart: 10_000, interestPart: 5_000,
            date: calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        )

        let contract = try #require(try LoanContractStore(context: context).contract(for: account.id))
        #expect(contract.paymentsMade == 1)
        #expect(contract.paidInterestTotal == 5_000)
    }

    @Test("Не-кредитный счёт и неположительное тело отбиваются, лента не меняется")
    func invalidInputIsRejected() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let date = calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
        let cash = try service.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 1_000, date: date
        )
        let loan = try makeLoan(context: context)
        let recorder = LoanPaymentRecorder(modelContext: context)

        #expect(throws: LoanPaymentError.self) {
            try recorder.recordScheduledPayment(
                account: cash, principalPart: 100, interestPart: 0, date: date
            )
        }
        // Платёж ниже процентов периода: тела в нём нет, гасить нечего.
        #expect(throws: LoanPaymentError.self) {
            try recorder.recordScheduledPayment(
                account: loan, principalPart: 0, interestPart: 17_912, date: date
            )
        }
        #expect(balance(loan, on: date) == -1_200_000)
        #expect(try LoanContractStore(context: context).contract(for: loan.id) == nil)
    }
}
