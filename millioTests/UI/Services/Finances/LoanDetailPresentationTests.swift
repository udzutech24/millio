import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф4 кредита: витрина деталки против эталонного кредита спеки §4.5 и макета (ЭКРАН 1).
///
/// Тест интеграционный намеренно: счёт, договор и пять платежей проходят тем же путём, что и в
/// приложении (`LoanPaymentRecorder` → лента событий), а цифры экрана читаются из витрины. Проверка
/// только на `LoanScheduleEngine` не поймала бы расхождение ленты и графика — а именно из ленты
/// деталка берёт остаток (спека Р6).
@Suite(.serialized)
@MainActor
struct LoanDetailPresentationTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    /// Кредит взят 15 марта 2026, первый платёж — 15 апреля 2026 (макет).
    private var firstPaymentDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    }

    private var openingDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
    }

    /// Момент оценки зафиксирован: пять платежей уже внесены, шестой ещё нет. От системных часов
    /// эталонные числа зависеть не должны.
    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    private func makeReferenceLoan(context: ModelContext) throws -> (Account, LoanContract) {
        let account = try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: 1_200_000,
            loanMeta: LoanMeta(
                principal: 1_200_000, rate: 18.9, monthlyPayment: nil, paymentDay: 15,
                termEnd: nil, scheduleType: .annuity, insurance: nil
            ),
            date: openingDate
        )
        let contract = try LoanContractStore(context: context).upsert(accountID: account.id) {
            $0.principal = 1_200_000
            $0.annualRatePercent = 18.9
            $0.termPeriods = 60
            $0.firstPaymentDate = firstPaymentDate
            $0.scheduleType = .annuity
            $0.frequency = .monthly
        }
        try context.save()
        return (account, contract)
    }

    private func presentation(account: Account, contract: LoanContract) -> LoanDetailPresentation {
        // Тот же вход, что собирает `AccountDetailView`: остаток — из ленты, прогресс — из договора.
        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: asOf)
        return LoanDetailPresentation.make(
            terms: contract.terms,
            outstandingPrincipal: max(-balance, 0),
            paymentsMade: contract.paymentsMade,
            paidInterestTotal: contract.paidInterestTotal,
            currency: account.currency,
            calendar: calendar
        )
    }

    /// Пять плановых платежей тем же путём, что и кнопка «Внести платёж».
    private func payFivePayments(account: Account, contract: LoanContract, context: ModelContext) throws {
        let recorder = LoanPaymentRecorder(modelContext: context)
        for _ in 0..<5 {
            let current = presentation(account: account, contract: contract)
            try recorder.recordScheduledPayment(
                account: account,
                principalPart: try #require(current.nextPaymentPrincipal),
                interestPart: try #require(current.nextPaymentInterest),
                date: try #require(current.nextPaymentDate)
            )
        }
    }

    // MARK: - Эталонный кредит

    @Test("Деталка эталонного кредита после 5 платежей — 8 контрольных чисел макета")
    func referenceLoanAfterFivePayments() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)

        try payFivePayments(account: account, contract: contract, context: context)
        let result = presentation(account: account, contract: contract)

        #expect(rubles(result.outstandingPrincipal) == 1_137_241)
        #expect(rubles(result.paidPrincipal) == 62_759)
        // 5,2 % макета: сравниваем число, а не строку — форматирование зависит от локали.
        #expect(rubles(result.progress * 1000) == 52)
        #expect(rubles(try #require(result.nextPayment)) == 31_063)
        #expect(rubles(try #require(result.nextPaymentPrincipal)) == 13_151)
        #expect(rubles(try #require(result.nextPaymentInterest)) == 17_912)
        #expect(rubles(result.paidInterestTotal) == 92_554)
    }

    @Test("Даты деталки: следующий платёж 15 сентября 2026, закрытие 15 марта 2031")
    func referenceLoanDates() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)

        try payFivePayments(account: account, contract: contract, context: context)
        let result = presentation(account: account, contract: contract)

        #expect(result.nextPaymentDate == calendar.date(from: DateComponents(year: 2026, month: 9, day: 15)))
        // График строится от фактического остатка, но исходная дата закрытия не «уезжает»:
        // 55 платежей от 15 сентября 2026 дают ровно 60-й платёж исходного графика.
        #expect(result.payoffDate == calendar.date(from: DateComponents(year: 2031, month: 3, day: 15)))
        #expect(result.paymentsAhead == 55)
        #expect(result.termMonths == 60)
        #expect(result.paymentsMade == 5)
    }

    @Test("До первого платежа деталка показывает полный долг и нулевой прогресс")
    func freshLoanShowsFullDebt() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)

        let result = presentation(account: account, contract: contract)

        #expect(rubles(result.outstandingPrincipal) == 1_200_000)
        #expect(result.paidPrincipal == 0)
        #expect(result.progress == 0)
        #expect(result.paymentsAhead == 60)
        #expect(rubles(try #require(result.nextPayment)) == 31_063)
        #expect(result.nextPaymentDate == firstPaymentDate)
    }

    // MARK: - Ф3.4: витрина плановой операции

    @Test("Без плана в Cashflow витрина не обещает платёж — кнопка «Внести платёж» скрыта")
    func presentationWithoutPlanHidesPaymentAction() {
        let terms = LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 60,
            firstPaymentDate: firstPaymentDate
        )
        let result = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: 1_200_000, paymentsMade: 0,
            paidInterestTotal: 0, currency: "RUB", calendar: calendar
        )

        #expect(result.plannedPaymentDate == nil)
        // Ближайший платёж по графику при этом существует: витрина различает «график знает дату»
        // и «в Cashflow лежит операция, которую можно применить».
        #expect(result.nextPaymentDate != nil)
    }

    @Test("Дата плановой операции доезжает до витрины и совпадает с ближайшим платежом графика")
    func plannedPaymentDateMatchesSchedule() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)

        let plannedRow = try #require(
            try LoanPlannedPaymentScheduler.openPlannedRow(accountID: account.id, context: context)
        )
        let view = LoanDetailPresentation.make(
            terms: contract.terms,
            outstandingPrincipal: 1_200_000,
            paymentsMade: contract.paymentsMade,
            paidInterestTotal: contract.paidInterestTotal,
            currency: account.currency,
            plannedPaymentDate: plannedRow.transactionDate,
            calendar: calendar
        )

        #expect(view.plannedPaymentDate == plannedRow.transactionDate)
        // Сравнение по дню, а не по мгновению: план собирается календарём системной зоны
        // (`LoanContractStore.upsert` → `sync`), а витрина в этом тесте считает в UTC. На экране
        // это один и тот же день, и именно он — обещание пользователю.
        #expect(Calendar(identifier: .gregorian).isDate(
            try #require(view.plannedPaymentDate),
            inSameDayAs: try #require(view.nextPaymentDate)
        ))
        // Шаг плана — та же периодичность, что у договора, словами Cashflow.
        #expect(view.plannedRecurrenceTitle == CashflowRecurrenceRule.monthly.displayName)
    }

    @Test("Двухмесячный кредит показывает шаг плана «раз в 2 месяца»")
    func everyTwoMonthsShowsOwnRecurrenceTitle() {
        let terms = LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 30,
            firstPaymentDate: firstPaymentDate, scheduleType: .annuity, frequency: .every2Months
        )
        let result = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: 1_200_000, paymentsMade: 0,
            paidInterestTotal: 0, currency: "RUB",
            plannedPaymentDate: firstPaymentDate, calendar: calendar
        )

        #expect(result.plannedRecurrenceTitle == CashflowRecurrenceRule.every2Months.displayName)
    }

    @Test("«Внести платёж» применяет плановую операцию: долг падает, план встаёт на следующий период")
    func paymentButtonAppliesPlannedOperation() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        let before = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: .distantFuture)
        let plannedBefore = try #require(
            try LoanPlannedPaymentScheduler.openPlannedRow(accountID: account.id, context: context)
        )

        // Тот же вызов, что делает кнопка на деталке.
        try LoanPlannedPaymentScheduler.applyNextPlannedPayment(accountID: account.id, context: context)

        let after = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: .distantFuture)
        #expect(after > before) // долг-обязательство лежит минусом, платёж двигает его к нулю
        #expect(contract.paymentsMade == 1)
        #expect(plannedBefore.hasAppliedBalanceEffect)

        let plannedAfter = try #require(
            try LoanPlannedPaymentScheduler.openPlannedRow(accountID: account.id, context: context)
        )
        #expect(plannedAfter.transactionDate > plannedBefore.transactionDate)
        // Второй строки расхода на тот же платёж не появилось: план стал фактом.
        let facts = try context.fetch(FetchDescriptor<CashflowTransaction>())
            .filter { $0.importSourceRaw == LoanPaymentCashflowProjector.importSource }
        #expect(facts.count == 2) // применённый факт + следующий план
    }

    // MARK: - Границы

    @Test("Закрытый кредит: платежей впереди нет, кнопка платежа гаснет")
    func fullyRepaidLoanHasNoNextPayment() {
        let terms = LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 60,
            firstPaymentDate: firstPaymentDate
        )
        let result = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: 0, paymentsMade: 60,
            paidInterestTotal: 663_760, currency: "RUB", calendar: calendar
        )

        #expect(result.nextPayment == nil)
        #expect(result.paymentsAhead == 0)
        #expect(result.payoffDate == nil)
        #expect(result.progress == 1)
    }

    @Test("Переплата (баланс ушёл в плюс) не даёт отрицательного остатка и прогресса больше 100 %")
    func overpaidLoanIsClamped() {
        let terms = LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 60,
            firstPaymentDate: firstPaymentDate
        )
        let result = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: -5_000, paymentsMade: 60,
            paidInterestTotal: 663_760, currency: "RUB", calendar: calendar
        )

        #expect(result.outstandingPrincipal == 0)
        #expect(result.progress == 1)
        #expect(result.paidPrincipal == 1_200_000)
    }

    @Test("Досрочно внесённое тело пересчитывает платёж под оставшийся срок")
    func extraPrincipalRecalculatesPayment() throws {
        let terms = LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 60,
            firstPaymentDate: firstPaymentDate
        )
        // Остаток после 5 платежей минус досрочные 200 000. Пока срок договора не тронут, витрина
        // показывает сценарий «уменьшить платёж» — те же 25 600 ₽, что считает `LoanPrepaymentPlanner`.
        // Выбор сценария («срок» или «платёж») — предмет Ф6: он правит договор, а не витрину.
        let result = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: 937_241, paymentsMade: 5,
            paidInterestTotal: 92_554, currency: "RUB", calendar: calendar
        )

        #expect(result.paymentsAhead == 55)
        #expect(rubles(try #require(result.nextPayment)) == 25_600)
    }
}
