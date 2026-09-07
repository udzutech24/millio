import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф3.3: платёж по кредиту живёт плановой операцией Cashflow, а не фактом на кнопке.
///
/// Эталон: 1 200 000 ₽ под 12% годовых на 60 месяцев, первый платёж 15.04.2026. Период — 1%,
/// аннуитет 26 693,34 ₽, из них проценты первого периода 12 000 ₽, тело 14 693,34 ₽. Числа
/// проверяемы вручную (`P·i·(1+i)ⁿ/((1+i)ⁿ−1)`), поэтому тесты не пересказывают расчётное ядро.
@Suite(.serialized)
@MainActor
struct LoanPlannedPaymentSchedulerTests {

    // MARK: - Харнесс

    /// Календарь системной зоны: сюда же по умолчанию ходит `sync` из `LoanContractStore`, и
    /// сравнивать даты из двух разных зон было бы гаданием на границе суток.
    private var calendar: Calendar { Calendar(identifier: .gregorian) }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeLoan(
        context: ModelContext,
        principal: Decimal = 1_200_000,
        rate: Decimal = 12,
        termPeriods: Int = 60,
        frequency: LoanPaymentFrequency = .monthly
    ) throws -> (Account, LoanContract) {
        let account = try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: principal,
            date: day(2026, 3, 15)
        )
        let contract = try LoanContractStore(context: context).upsert(accountID: account.id) { contract in
            contract.principal = principal
            contract.annualRatePercent = rate
            contract.termPeriods = termPeriods
            contract.firstPaymentDate = day(2026, 4, 15)
            contract.scheduleType = .annuity
            contract.frequency = frequency
        }
        try context.save()
        return (account, contract)
    }

    private func loanRows(_ context: ModelContext) throws -> [CashflowTransaction] {
        try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == LoanPaymentCashflowProjector.importSource }
            .sorted { $0.transactionDate < $1.transactionDate }
    }

    private func plannedRows(_ context: ModelContext) throws -> [CashflowTransaction] {
        try loanRows(context).filter {
            LoanPlannedPaymentScheduler.isPlannedRow($0) && !$0.hasAppliedBalanceEffect
        }
    }

    private func outstanding(_ account: Account) -> Decimal {
        LoanOutstanding.fromLedger(
            balance: AccountBalanceEngine.balanceAt(
                events: account.events ?? [],
                kind: .loan,
                on: .distantFuture
            )
        )
    }

    private func components(_ date: Date) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    // MARK: - Создание

    @Test("Договор заводит ровно одну плановую операцию с платежом и датой из графика")
    func contractCreatesSinglePlannedOperation() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, _) = try makeLoan(context: context)

        let rows = try plannedRows(context)
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.transactionType == .expense)
        #expect(row.currency == "RUB")
        #expect(row.note == "Автокредит")
        #expect(abs(row.amount - 26_693.34) < 0.01)
        #expect(components(row.transactionDate) == components(day(2026, 4, 15)))
        // Баланс счёта-источника план не двигает — с какого счёта уйдут деньги, кредит не знает.
        #expect(row.affectsCardBalance == false)
        #expect(row.recurrenceRule == .none)
        #expect(row.importReferenceKey == LoanPlannedPaymentScheduler.plannedReferenceKey(
            accountID: account.id,
            paymentIndex: 1
        ))

        // Повторный sync строк не добавляет.
        try LoanPlannedPaymentScheduler.sync(accountID: account.id, context: context)
        #expect(try plannedRows(context).count == 1)
    }

    @Test("Боевой путь создания счёта (AccountProductFactory + договор в одной транзакции) заводит план")
    func productFactoryCreationCreatesPlan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let command = CreateProductCommand(
            productType: .loan,
            name: "Ипотека",
            currency: "RUB",
            openingBalance: 1_200_000,
            metadata: .init(loan: LoanMeta(
                principal: 1_200_000, rate: 12, monthlyPayment: nil, paymentDay: 15,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ))
        )
        // Договор пишется тем же `graphEnricher` в том же transaction-контексте, что и в форме.
        _ = try AccountProductFactory(modelContext: context).create(command) { _, transactionContext in
            try LoanContractStore(context: transactionContext).upsert(accountID: command.accountID) { contract in
                contract.principal = 1_200_000
                contract.annualRatePercent = 12
                contract.termPeriods = 60
                contract.firstPaymentDate = self.day(2026, 4, 15)
                contract.scheduleType = .annuity
                contract.frequency = .monthly
            }
        }

        let rows = try plannedRows(context)
        #expect(rows.count == 1)
        #expect(abs(try #require(rows.first).amount - 26_693.34) < 0.01)
    }

    // MARK: - Применение

    @Test("Применение уменьшает тело долга на principalPart и сдвигает план")
    func applyReducesPrincipalAndMovesPlan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)

        try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)

        // Долг упал ровно на тело: проценты — плата за пользование, остаток по ним не падает.
        let expectedOutstanding = Decimal(1_200_000) - Decimal(string: "14693.34")!
        #expect(abs(outstanding(account) - expectedOutstanding) < Decimal(string: "0.01")!)
        #expect(contract.paymentsMade == 1)
        #expect(abs(contract.paidInterestTotal - 12_000) < Decimal(string: "0.01")!)

        // Строка Cashflow ровно одна — план стал фактом, второй проводки проектор не создал.
        #expect(planned.hasAppliedBalanceEffect)
        #expect(abs(planned.amount - 26_693.34) < 0.01)
        #expect(try loanRows(context).filter(\.hasAppliedBalanceEffect).count == 1)

        // На месте плана — следующий платёж месяцем позже.
        let next = try #require(try plannedRows(context).first)
        #expect(next.id != planned.id)
        #expect(components(next.transactionDate) == components(day(2026, 5, 15)))
        #expect(abs(next.amount - 26_693.34) < 0.01)
    }

    @Test("Повторное применение той же строки платёж не задваивает")
    func repeatedApplyIsRejected() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)

        try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)
        let outstandingAfterFirst = outstanding(account)

        #expect(throws: LoanPlannedPaymentError.self) {
            try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)
        }
        #expect(contract.paymentsMade == 1)
        #expect(outstanding(account) == outstandingAfterFirst)
        #expect(try loanRows(context).count == 2) // применённый факт + следующий план
    }

    // MARK: - Досрочка и закрытие

    @Test("Досрочка с новым платежом обновляет сумму плана")
    func prepaymentUpdatesPlannedAmount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, _) = try makeLoan(context: context)

        try LoanPaymentRecorder(modelContext: context).record(
            LoanExtraPaymentEntry(
                principalPart: 300_000,
                interestPart: 0,
                consumesPeriod: false,
                pinnedPayment: 20_000
            ),
            on: account,
            date: day(2026, 4, 1)
        )

        let rows = try plannedRows(context)
        #expect(rows.count == 1)
        #expect(abs(try #require(rows.first).amount - 20_000) < 0.01)
    }

    @Test("Полное погашение снимает плановую операцию")
    func fullRepaymentRemovesPlan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, _) = try makeLoan(context: context)

        // Сумма заведомо больше остатка: recorder клампит её по долгу.
        try LoanPaymentRecorder(modelContext: context).record(
            LoanExtraPaymentEntry(
                principalPart: 2_000_000,
                interestPart: 0,
                consumesPeriod: false,
                pinnedPayment: nil
            ),
            on: account,
            date: day(2026, 4, 1)
        )

        #expect(outstanding(account) == .zero)
        #expect(try plannedRows(context).isEmpty)
    }

    @Test("Удаление счёта не оставляет плановую операцию-сироту")
    func accountDeletionRemovesPlan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let (account, _) = try makeLoan(context: context)
        #expect(try plannedRows(context).count == 1)

        try service.softDelete(account, on: day(2026, 4, 1))
        #expect(try plannedRows(context).isEmpty)

        // Договор мягкое удаление переживает: возврат счёта должен вернуть и план.
        #expect(try LoanContractStore(context: context).contract(for: account.id) != nil)
    }

    @Test("Физическое удаление счёта уносит и договор, и план")
    func physicalDeletionRemovesContractAndPlan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let service = AccountsCoreService(modelContext: context)
        let (account, _) = try makeLoan(context: context)
        let accountID = account.id

        try service.physicallyDelete(account)

        #expect(try LoanContractStore(context: context).contract(for: accountID) == nil)
        #expect(try plannedRows(context).isEmpty)
    }

    // MARK: - Периодичность

    @Test("every2Months ведёт план шагом в два месяца")
    func everyTwoMonthsPlanStepsByTwoMonths() throws {
        #expect(LoanPlannedPaymentScheduler.recurrenceRule(for: .every2Months) == .every2Months)
        #expect(CashflowRecurrenceRule.every2Months.monthInterval == 2)

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (_, _) = try makeLoan(context: context, termPeriods: 30, frequency: .every2Months)

        let planned = try #require(try plannedRows(context).first)
        #expect(components(planned.transactionDate) == components(day(2026, 4, 15)))

        try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)

        let next = try #require(try plannedRows(context).first)
        #expect(components(next.transactionDate) == components(day(2026, 6, 15)))
    }

    // MARK: - Хук авто-применения

    @Test("Окно авто-применения проводит платёж по кредиту через recorder, а не balance-эффектом")
    func dueAutoApplyRoutesLoanPaymentThroughRecorder() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)

        let suiteName = "tests.loan.planned.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let scope = "millio_user_owner"
        defaults.set(day(2026, 4, 1), forKey: CashflowScheduledService.dueAutoApplyCheckpointKeyPrefix + scope)

        // Общий balance-эффект для кредита запрещён: он списал бы расход, не тронув долг.
        var genericApplies = 0
        let service = CashflowScheduledService(
            modelContext: context,
            defaults: defaults,
            scopeIdentifier: scope,
            now: { self.day(2026, 4, 20) },
            transactionsProvider: { (try? self.loanRows(context)) ?? [] },
            onTransactionsMutated: {},
            onResolveExchangeInfo: { _ in CashflowExchangeInfo(rate: nil, rateDate: nil, rateCurrency: nil) },
            onApplyRecurringToCard: { _ in },
            onApplyDuePlannedEffect: { _ in genericApplies += 1 },
            appliedNoticeStore: AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope),
            noticeAccountNameResolver: { _ in account.name },
            noticeTitleResolver: { _ in account.name }
        )

        let didApply = await service.applyDuePlannedTransactionsIfNeeded(referenceNow: day(2026, 4, 20))

        #expect(didApply)
        #expect(genericApplies == 0)
        #expect(planned.hasAppliedBalanceEffect)
        #expect(contract.paymentsMade == 1)
        let expectedOutstanding = Decimal(1_200_000) - Decimal(string: "14693.34")!
        #expect(abs(outstanding(account) - expectedOutstanding) < Decimal(string: "0.01")!)
        // Применение попало в журнал сводки — операция не проходит мимо «что применилось».
        let digest = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: scope).beginPresentation()
        #expect(try #require(digest).totalCount == 1)
    }

    // MARK: - Закрытый месяц

    @Test("Закрытый месяц Cashflow отбивает платёж целиком")
    func closedMonthRejectsWholePayment() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeLoan(context: context)
        let planned = try #require(try plannedRows(context).first)

        let monthStart = Calendar.autoupdatingCurrent
            .dateInterval(of: .month, for: planned.transactionDate)!.start
        context.insert(CashflowMonthClosureEvent(
            monthStart: monthStart,
            kind: .close,
            occurredAt: day(2026, 5, 1)
        ))
        try context.save()

        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try LoanPlannedPaymentScheduler.applyPlannedPayment(planned, context: context)
        }
        // Ни ленты, ни договора, ни признака применения: отбито до первой правки.
        #expect(outstanding(account) == 1_200_000)
        #expect(contract.paymentsMade == 0)
        #expect(contract.paidInterestTotal == .zero)
        #expect(planned.hasAppliedBalanceEffect == false)
        #expect(try plannedRows(context).count == 1)
    }
}
