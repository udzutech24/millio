import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф7 кредита: платёж по кредиту виден в Cashflow расходом, повторный прогон строк не задваивает
/// (спека §9.1, критерий приёмки 4). Страховку кредит не проводит (решение владельца 07.09).
@Suite(.serialized)
@MainActor
struct LoanPaymentCashflowProjectionTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
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
            date: day(2026, 3, 15)
        )
    }

    private func loanRows(_ context: ModelContext) throws -> [CashflowTransaction] {
        try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == LoanPaymentCashflowProjector.importSource }
    }

    @Test("Плановый платёж создаёт одну строку расхода на тело + проценты")
    func scheduledPaymentCreatesSingleExpense() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)

        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: account, principalPart: 13_151, interestPart: 17_912, date: day(2026, 4, 15)
        )

        let rows = try loanRows(context)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.transactionType == .expense)
        #expect(row.amount == 31_063)
        #expect(row.currency == "RUB")
        #expect(row.note == "Автокредит")
        // Баланс счёта-источника проводка не двигает: с какого счёта ушли деньги, кредит не знает.
        #expect(row.affectsCardBalance == false)
    }

    @Test("Повторная проекция того же платежа строку не задваивает")
    func repeatedProjectionIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let paymentID = UUID()

        let first = try LoanPaymentCashflowProjector.project(
            account: account, paymentID: paymentID, amount: 31_063,
            date: day(2026, 4, 15), context: context
        )
        let second = try LoanPaymentCashflowProjector.project(
            account: account, paymentID: paymentID, amount: 31_063,
            date: day(2026, 4, 15), context: context
        )
        try context.save()

        #expect(first == 1)
        #expect(second == 0)
        #expect(try loanRows(context).count == 1)
    }

    @Test("Страховка в договоре строки не создаёт: кредит её не проводит")
    func insuranceInContractCreatesNoRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        // Поле остаётся в схеме (V12 заморожена) и приезжает из бэкапа — но платёж его не читает.
        try LoanContractStore(context: context).upsert(accountID: account.id) {
            $0.principal = 1_200_000
            $0.annualRatePercent = 18.9
            $0.termPeriods = 60
            $0.insuranceAmount = 1_500
        }
        try context.save()

        try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
            account: account, principalPart: 13_151, interestPart: 17_912, date: day(2026, 4, 15)
        )

        // Строк две: факт платежа и плановая операция следующего (Ф3.3) — страховки нет ни в одной.
        let rows = try loanRows(context)
        let facts = rows.filter { !LoanPlannedPaymentScheduler.isPlannedRow($0) }
        #expect(facts.count == 1)
        #expect(try #require(facts.first).amount == 31_063)
        #expect(rows.allSatisfy { $0.expenseCategoryRaw != ExpenseCategory.insurance.rawValue })

        // Долг двигает только тело: страховка на него не влияла и раньше.
        let balance = AccountBalanceEngine.balanceAt(
            events: account.events ?? [], kind: .loan, on: day(2026, 4, 15)
        )
        #expect(balance == -1_186_849)
    }

    @Test("Досрочное погашение даёт одну строку на внесённое тело")
    func prepaymentCreatesSingleRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        try LoanContractStore(context: context).upsert(accountID: account.id) {
            $0.principal = 1_200_000
            $0.insuranceAmount = 1_500
        }
        try context.save()

        try LoanPaymentRecorder(modelContext: context).record(
            LoanExtraPaymentEntry(
                principalPart: 200_000, interestPart: .zero, consumesPeriod: false, pinnedPayment: nil
            ),
            on: account,
            date: day(2026, 4, 20)
        )

        let rows = try loanRows(context)
        #expect(rows.count == 1)
        #expect(rows.first?.amount == 200_000)
        #expect(rows.first?.expenseCategoryRaw == ExpenseCategory.other.rawValue)
    }

    @Test("Закрытый месяц отбивает платёж целиком: ни строки, ни движения долга")
    func closedMonthRejectsWholePayment() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let paymentDate = day(2026, 4, 15)
        context.insert(CashflowMonthClosureEvent(
            monthStart: paymentDate, kind: .close, occurredAt: paymentDate
        ))
        try context.save()

        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try LoanPaymentRecorder(modelContext: context).recordScheduledPayment(
                account: account, principalPart: 13_151, interestPart: 17_912, date: paymentDate
            )
        }

        #expect(try loanRows(context).isEmpty)
        let balance = AccountBalanceEngine.balanceAt(
            events: account.events ?? [], kind: .loan, on: paymentDate
        )
        #expect(balance == -1_200_000)
        #expect(try LoanContractStore(context: context).contract(for: account.id) == nil)
    }
}
