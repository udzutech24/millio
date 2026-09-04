import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф6 кредита: витрина листа досрочного погашения (макет, ЭКРАН 4) и путь подтверждения.
///
/// Эталон — спека §4.5: кредит 1 200 000 ₽ · 18,9% · 60 мес · аннуитет, 5 платежей внесено,
/// досрочно 200 000 ₽. Тексты не сверяются дословно (они зависят от языка приложения) — сверяются
/// состав листа и числа, которые в эти тексты попадают.
@Suite(.serialized)
@MainActor
struct LoanPrepaymentPresentationTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var firstPaymentDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 4, day: 15))!
    }

    private var openingDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
    }

    /// Момент оценки: пять платежей внесены, шестой ещё нет.
    private var asOf: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    private var referenceTerms: LoanTerms {
        LoanTerms(
            principal: 1_200_000, annualRatePercent: 18.9, termPeriods: 60,
            firstPaymentDate: firstPaymentDate
        )
    }

    private func rubles(_ value: Decimal) -> Decimal {
        var result = Decimal()
        var mutable = value
        NSDecimalRound(&result, &mutable, 0, .plain)
        return result
    }

    private func money(_ value: Decimal) -> String {
        LoanMoneyFormat.money(value, currency: "RUB")
    }

    /// Остаток после 5 платежей по эталонному кредиту — вход листа.
    private var outstandingAfterFive: Decimal {
        LoanScheduleEngine.schedule(terms: referenceTerms, calendar: calendar)
            .outstandingPrincipal(afterPayments: 5)
    }

    private func sheet(
        amount: Decimal,
        strategy: LoanPrepaymentStrategy = .term,
        terms: LoanTerms? = nil,
        outstanding: Decimal? = nil,
        paymentsMade: Int = 5
    ) -> LoanPrepaymentPresentation {
        let terms = terms ?? referenceTerms
        return LoanPrepaymentPresentation.make(
            terms: terms,
            outstandingPrincipal: outstanding
                ?? LoanScheduleEngine.schedule(terms: terms, calendar: calendar)
                    .outstandingPrincipal(afterPayments: paymentsMade),
            paymentsMade: paymentsMade,
            amount: amount,
            strategy: strategy,
            currency: "RUB",
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        )
    }

    // MARK: - Состав листа

    @Test("Сумма не введена: только подсказка, подтверждать нечего")
    func idleSheetHasNothingToConfirm() {
        let result = sheet(amount: 0)
        #expect(result.mode == .idle)
        #expect(result.options.isEmpty)
        #expect(result.diff.isEmpty)
        #expect(result.outcome == nil)
        #expect(result.entry == nil)
        #expect(result.canConfirm == false)
        // Подсказка «ближайший платёж … останется прежним» есть и до ввода суммы.
        #expect(!result.hint.isEmpty)
    }

    @Test("Досрочно 200 000 ₽: две опции, предвыбран «Срок», тег выгоды у него")
    func prepaymentSheetMatchesMockup() throws {
        let result = sheet(amount: 200_000)

        #expect(result.mode == .prepayment)
        #expect(result.selectedStrategy == .term)
        #expect(result.options.map(\.strategy) == [.term, .payment])
        // «выгоднее на N ₽» — только у выгодного сценария, у второго тега нет.
        #expect(result.options[0].tag != nil)
        #expect(result.options[1].tag == nil)
        #expect(result.options.allSatisfy { !$0.note.isEmpty })

        #expect(result.diff.map(\.id) == ["debt", "payment", "payoff", "interest"])
        #expect(result.diff[0].before == money(1_137_241))
        #expect(result.diff[0].after == money(937_241))
        // Платёж в сценарии «срок» не меняется — строка показывает «без изменений».
        #expect(result.diff[1].after == nil)
        #expect(result.diff[3].after == money(344_435))
        #expect(result.diff[3].afterStyle == .positive)

        let outcome = try #require(result.outcome)
        #expect(outcome.value == money(226_771))
        #expect(outcome.style == .positive)
        #expect(result.confirmTitle.contains(money(200_000)))
    }

    @Test("Сценарий «платёж»: платёж падает до 25 600 ₽, экономия 100 455 ₽")
    func paymentStrategySheetShowsNewPayment() throws {
        let result = sheet(amount: 200_000, strategy: .payment)

        #expect(result.selectedStrategy == .payment)
        #expect(result.diff[1].after == money(25_600))
        #expect(try #require(result.outcome).value == money(100_455))
        let entry = try #require(result.entry)
        let pinned = try #require(entry.pinnedPayment)
        #expect(rubles(pinned) == 25_600)
    }

    @Test("Полное погашение: закрытие кредита вместо отрицательных дельт")
    func payoffSheetShowsClosure() throws {
        let result = sheet(amount: 2_000_000)

        #expect(result.mode == .payoff)
        // Выбирать нечего — радио-строк нет.
        #expect(result.options.isEmpty)
        #expect(result.selectedStrategy == nil)
        #expect(result.diff[0].after == money(0))
        #expect(result.diff[3].after == money(0))
        // Спишется остаток, а не введённая сумма.
        let entry = try #require(result.entry)
        #expect(rubles(entry.principalPart) == 1_137_241)
        #expect(result.confirmTitle.contains(money(1_137_241)))
        #expect(try #require(result.outcome).value == money(571_206))
    }

    @Test("Недоплата: выбора нет, вместо экономии — рост срока и переплаты")
    func underpaymentSheetShowsGrowth() throws {
        let result = sheet(amount: 25_000)

        #expect(result.mode == .underpayment)
        #expect(result.options.isEmpty)
        #expect(result.selectedStrategy == nil)
        #expect(result.diff[0].after == money(1_130_152))
        // Платёж дальше прежний.
        #expect(result.diff[1].after == nil)
        // Проценты меряются от того же момента, что и «было»: рост, а не мнимая экономия.
        #expect(result.diff[3].after == money(571_206 + 8_257))
        #expect(result.diff[3].afterStyle == .negative)

        let outcome = try #require(result.outcome)
        #expect(outcome.value == money(8_257))
        #expect(outcome.style == .negative)
        // «Срок вырастет на N платежей» — вторая строка карточки.
        #expect(outcome.detail != nil)

        let entry = try #require(result.entry)
        #expect(entry.consumesPeriod)
        #expect(rubles(entry.principalPart) == 7_088)
        #expect(rubles(entry.interestPart) == 17_912)
    }

    @Test("Недоплата ниже процентов периода: долг не двигается")
    func underpaymentBelowInterestKeepsDebt() throws {
        let result = sheet(amount: 10_000)

        #expect(result.mode == .underpayment)
        // Остаток не меняется — строка «Остаток долга» без «стало».
        #expect(result.diff[0].after == nil)
        #expect(try #require(result.outcome).value == money(10_000))
        #expect(try #require(result.entry).principalPart == .zero)
    }

    @Test("Дифференцированный график: одна опция вместо двух")
    func differentiatedSheetHasSingleOption() throws {
        var terms = referenceTerms
        terms.scheduleType = .differentiated
        // Выбор «платёж» недоступен — витрина обязана вернуться к «сроку», а не показать пустоту.
        let result = sheet(amount: 200_000, strategy: .payment, terms: terms)

        #expect(result.mode == .prepayment)
        #expect(result.options.map(\.strategy) == [.term])
        #expect(result.selectedStrategy == .term)
        // Единственный сценарий не сравнивается ни с чем — тега выгоды нет.
        #expect(result.options[0].tag == nil)
        #expect(try #require(result.outcome).value == money(159_075))
        #expect(try #require(result.entry).pinnedPayment == nil)
    }

    // MARK: - Путь подтверждения

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

    private func outstanding(_ account: Account) -> Decimal {
        max(-AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: asOf), 0)
    }

    private func detail(_ account: Account, _ contract: LoanContract) -> LoanDetailPresentation {
        LoanDetailPresentation.make(
            terms: contract.terms,
            outstandingPrincipal: outstanding(account),
            paymentsMade: contract.paymentsMade,
            paidInterestTotal: contract.paidInterestTotal,
            currency: account.currency,
            calendar: calendar
        )
    }

    private func payFivePayments(_ account: Account, _ contract: LoanContract, _ context: ModelContext) throws {
        let recorder = LoanPaymentRecorder(modelContext: context)
        for _ in 0..<5 {
            let current = detail(account, contract)
            try recorder.recordScheduledPayment(
                account: account,
                principalPart: try #require(current.nextPaymentPrincipal),
                interestPart: try #require(current.nextPaymentInterest),
                date: try #require(current.nextPaymentDate)
            )
        }
    }

    @Test("Подтверждение «срока»: долг −200 000 ₽, деталка и график считают от нового остатка")
    func confirmingTermStrategyRecalculatesScreens() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account, contract, context)

        let before = outstanding(account)
        #expect(rubles(before) == 1_137_241)

        let presentation = LoanPrepaymentPresentation.make(
            terms: contract.terms, outstandingPrincipal: before,
            paymentsMade: contract.paymentsMade, amount: 200_000, strategy: .term,
            currency: account.currency, calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        try LoanPaymentRecorder(modelContext: context).record(
            try #require(presentation.entry), on: account, date: asOf
        )

        // Долг уменьшился ровно на внесённую сумму — проценты в досрочке не участвуют.
        #expect(before - outstanding(account) == 200_000)
        #expect(rubles(outstanding(account)) == 937_241)
        // Период не израсходован: ближайший платёж остаётся шестым.
        #expect(contract.paymentsMade == 5)
        #expect(rubles(try #require(contract.paymentOverride)) == 31_063)

        let after = detail(account, contract)
        #expect(after.paymentsAhead == 42)
        #expect(rubles(try #require(after.nextPayment)) == 31_063)
        #expect(after.payoffDate == calendar.date(from: DateComponents(year: 2030, month: 2, day: 15)))

        let schedule = LoanSchedulePresentation.make(
            terms: contract.terms, outstandingPrincipal: outstanding(account),
            paymentsMade: contract.paymentsMade, currency: account.currency,
            calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        #expect(schedule.paymentsAhead == 42)
        #expect(schedule.rows.count == 47)
    }

    @Test("Подтверждение «платежа»: срок прежний, платёж 25 600 ₽")
    func confirmingPaymentStrategyKeepsTerm() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account, contract, context)

        let presentation = LoanPrepaymentPresentation.make(
            terms: contract.terms, outstandingPrincipal: outstanding(account),
            paymentsMade: contract.paymentsMade, amount: 200_000, strategy: .payment,
            currency: account.currency, calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        try LoanPaymentRecorder(modelContext: context).record(
            try #require(presentation.entry), on: account, date: asOf
        )

        let after = detail(account, contract)
        #expect(rubles(outstanding(account)) == 937_241)
        // Число платежей прежнее, а платёж — новый. Без закрепления в договоре экран показал бы
        // 42 платежа по 31 063 ₽, то есть чужой сценарий.
        #expect(after.paymentsAhead == 55)
        #expect(rubles(try #require(after.nextPayment)) == 25_600)
    }

    @Test("Подтверждение недоплаты: период израсходован, долг сдвинулся только на тело")
    func confirmingUnderpaymentConsumesPeriod() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account, contract, context)

        let before = outstanding(account)
        let presentation = LoanPrepaymentPresentation.make(
            terms: contract.terms, outstandingPrincipal: before,
            paymentsMade: contract.paymentsMade, amount: 25_000, strategy: .term,
            currency: account.currency, calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        let paidInterestBefore = contract.paidInterestTotal
        try LoanPaymentRecorder(modelContext: context).record(
            try #require(presentation.entry), on: account, date: asOf
        )

        #expect(rubles(before - outstanding(account)) == 7_088)
        #expect(contract.paymentsMade == 6)
        #expect(rubles(contract.paidInterestTotal - paidInterestBefore) == 17_912)
        // Платёж дальше прежний, а срок вырос: 55 платежей впереди при 6 внесённых.
        let after = detail(account, contract)
        #expect(rubles(try #require(after.nextPayment)) == 31_063)
        #expect(after.paymentsAhead == 55)
    }

    @Test("Полное погашение: долг обнуляется, лента в плюс не уходит")
    func confirmingPayoffZeroesDebt() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account, contract, context)

        let presentation = LoanPrepaymentPresentation.make(
            terms: contract.terms, outstandingPrincipal: outstanding(account),
            paymentsMade: contract.paymentsMade, amount: 5_000_000, strategy: .term,
            currency: account.currency, calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        try LoanPaymentRecorder(modelContext: context).record(
            try #require(presentation.entry), on: account, date: asOf
        )

        // Ноль «с точностью до копейки», а не абсолютный: SwiftData хранит `Decimal` через double,
        // и сумма события полного погашения возвращается из стора с пылью ~1e-9 от миллиона.
        // Продуктовый ноль обеспечивает кламп `AccountDetailView.loanOutstandingPrincipal`.
        #expect(outstanding(account) < Decimal(1) / 100)
        // Счёт-обязательство не имеет права стать активом: баланс не уходит в плюс.
        #expect(AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: asOf) <= .zero)
        #expect(detail(account, contract).paymentsAhead == 0)
        // То, что увидит экран: остаток ровно ноль, а значит и «Досрочно» уже не нажать.
        let ledger = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: asOf)
        #expect(LoanOutstanding.fromLedger(balance: ledger) == .zero)
    }

    @Test("Остаток долга: пыль ниже копейки — ноль, копейка и выше — долг")
    func ledgerDustIsNotDebt() {
        #expect(LoanOutstanding.fromLedger(balance: -0.000000009) == .zero)
        #expect(LoanOutstanding.fromLedger(balance: Decimal(1) / 100) == .zero)
        #expect(LoanOutstanding.fromLedger(balance: -(Decimal(1) / 100)) == Decimal(1) / 100)
        #expect(LoanOutstanding.fromLedger(balance: -1_137_241) == 1_137_241)
        // Счёт в плюсе долгом не становится.
        #expect(LoanOutstanding.fromLedger(balance: 500) == .zero)
    }
}
