import Foundation
import SwiftData
import Testing
@testable import millio

/// БАГ 4 (release-2.0-blockers): плановый платёж, применённый ЗАРАНЕЕ (дата плана впереди реального
/// момента оплаты), обязан быть виден и витрине «на сегодня», и клампу второго платежа сразу же —
/// иначе долг на экране не двигается, а следующий платёж клампится по неверному (завышенному)
/// остатку и может увести кредит в плюс. Регрессия для `LoanPlannedPaymentScheduler.applyPlannedPayment`
/// (millio/Core/AccountsCore/Loan/LoanPlannedPaymentScheduler.swift:203).
///
/// Дата плана берётся динамически (`Date() + 10 дней`), а не константой: правка клампит по голому
/// `Date()`, не инжектируемому — если дата не окажется реально в будущем на момент запуска,
/// `min(transactionDate, Date())` вырождается в no-op и тест перестаёт что-либо проверять.
@Suite(.serialized)
@MainActor
struct LoanPlannedPaymentTodayVisibilityTests {

    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func futurePaymentDate() -> Date {
        calendar.date(byAdding: .day, value: 10, to: Date())!
    }

    private func makeLoan(context: ModelContext) throws -> Account {
        let account = try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: 1_200_000,
            date: Date()
        )
        _ = try LoanContractStore(context: context).upsert(accountID: account.id) { contract in
            contract.principal = 1_200_000
            contract.annualRatePercent = 12
            contract.termPeriods = 60
            contract.firstPaymentDate = futurePaymentDate()
            contract.scheduleType = .annuity
            contract.frequency = .monthly
        }
        try context.save()
        return account
    }

    private func plannedRows(_ context: ModelContext) throws -> [CashflowTransaction] {
        try context.fetch(FetchDescriptor<CashflowTransaction>()).filter {
            $0.importSourceRaw == LoanPaymentCashflowProjector.importSource
                && LoanPlannedPaymentScheduler.isPlannedRow($0)
                && !$0.hasAppliedBalanceEffect
        }
    }

    /// В отличие от хелпера `outstanding()` в LoanPlannedPaymentSchedulerTests (тот сознательно
    /// берёт `.distantFuture`, как это делает `nextPayment()`), здесь нужен именно срез «на сегодня»
    /// — ровно то, что показывает витрина (`AccountDetailView.balanceToday`/`loanOutstandingPrincipal`).
    private func outstandingToday(_ account: Account) -> Decimal {
        LoanOutstanding.fromLedger(
            balance: AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: Date())
        )
    }

    @Test("Досрочная оплата видна витрине «на сегодня» сразу после применения")
    func earlyPaymentVisibleToday() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)
        #expect(planned.transactionDate > Date())

        // Досрочно, за 10 дней до плановой даты.
        try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)

        // До фикса: balanceAt(on: Date()) исключал событие с будущей датой — долг «на сегодня»
        // выглядел непогашенным (1 200 000), прогресс на экране не рос.
        let expectedOutstanding = Decimal(1_200_000) - Decimal(string: "14693.34")!
        #expect(abs(outstandingToday(account) - expectedOutstanding) < Decimal(string: "0.5")!)
    }

    @Test("Кламп второго платежа видит уже списанную сумму и не уводит долг в плюс")
    func secondPaymentClampSeesEarlyPayment() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)

        try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)

        // Просьба погасить весь ИСХОДНЫЙ остаток (1 200 000), как будто досрочного платежа не было.
        // До фикса: клампа считала остаток «на сегодня» по событию, которое всё ещё не видела
        // (оно лежало в будущем) — весь 1 200 000 проходил клампом целиком, и полная картина ленты
        // (любая дата, включая будущую дату первого события) уходила в плюс.
        try LoanPaymentRecorder(modelContext: context).record(
            LoanExtraPaymentEntry(
                principalPart: 1_200_000,
                interestPart: 0,
                consumesPeriod: false,
                pinnedPayment: nil
            ),
            on: account,
            date: Date()
        )

        // Полная картина ленты (любая дата — весь кредит уже выплачен) не должна показывать актив.
        let fullLedgerBalance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: .distantFuture)
        #expect(fullLedgerBalance <= 0)
    }
}
