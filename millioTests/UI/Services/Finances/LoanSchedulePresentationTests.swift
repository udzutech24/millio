import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5 кредита: витрина экрана «График платежей» против эталонного кредита спеки §4.5 и макета
/// (ЭКРАН 3).
///
/// Как и в Ф4, путь интеграционный: счёт, договор и пять платежей проходят через
/// `LoanPaymentRecorder`, остаток берётся из ленты событий — то же, что делает `AccountDetailView`.
/// Проверка на слое витрины, а не скриншотом: цифры экрана должны сходиться с ядром.
@Suite(.serialized)
@MainActor
struct LoanSchedulePresentationTests {

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

    /// Момент оценки зафиксирован: пять платежей внесены, шестой ещё нет.
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

    // MARK: - Харнесс эталонного кредита

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

    private func outstanding(account: Account) -> Decimal {
        max(-AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .loan, on: asOf), 0)
    }

    private func detail(account: Account, contract: LoanContract) -> LoanDetailPresentation {
        LoanDetailPresentation.make(
            terms: contract.terms,
            outstandingPrincipal: outstanding(account: account),
            paymentsMade: contract.paymentsMade,
            paidInterestTotal: contract.paidInterestTotal,
            currency: account.currency,
            calendar: calendar
        )
    }

    private func schedule(account: Account, contract: LoanContract) -> LoanSchedulePresentation {
        LoanSchedulePresentation.make(
            terms: contract.terms,
            outstandingPrincipal: outstanding(account: account),
            paymentsMade: contract.paymentsMade,
            currency: account.currency,
            calendar: calendar,
            locale: Locale(identifier: "ru_RU")
        )
    }

    private func payFivePayments(account: Account, contract: LoanContract, context: ModelContext) throws {
        let recorder = LoanPaymentRecorder(modelContext: context)
        for _ in 0..<5 {
            let current = detail(account: account, contract: contract)
            try recorder.recordScheduledPayment(
                account: account,
                principalPart: try #require(current.nextPaymentPrincipal),
                interestPart: try #require(current.nextPaymentInterest),
                date: try #require(current.nextPaymentDate)
            )
        }
    }

    // MARK: - Эталонный кредит

    @Test("График эталонного кредита: 60 строк, 5 внесённых, текущий период — шестой")
    func referenceScheduleStructure() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account: account, contract: contract, context: context)

        let result = schedule(account: account, contract: contract)

        #expect(result.rows.count == 60)
        #expect(result.paymentsMade == 5)
        #expect(result.paymentsAhead == 55)
        #expect(result.rows.prefix(5).allSatisfy { $0.isPaid })
        #expect(result.rows.dropFirst(5).allSatisfy { !$0.isPaid })
        #expect(result.rows.filter { $0.isCurrent }.map { $0.index } == [6])
        // Строка «55 впереди» на деталке и число невнесённых строк экрана — одно и то же число.
        #expect(result.paymentsAhead == detail(account: account, contract: contract).paymentsAhead)
        // Индексы сквозные: внесённое прошлое и будущее не пересекаются и не рвутся.
        #expect(result.rows.map { $0.index } == Array(1...60))
    }

    @Test("Доли тела платежей 1–11 растут по графику ядра: 39…46 %")
    func principalSharesOfFirstPayments() throws {
        let result = LoanSchedulePresentation.make(
            terms: referenceTerms, outstandingPrincipal: 1_200_000, paymentsMade: 0,
            currency: "RUB", calendar: calendar, locale: Locale(identifier: "ru_RU")
        )

        // Числа — из `LoanScheduleEngine`, не из колонки «Тело %» макета: та расходится с самим же
        // макетом (шестой платёж 13 151 / 31 063 = 42,3 %, в таблице макета — 43 %). Эталон здесь —
        // спека §4.5, все её числа сошлись в ноль ещё в Ф2.
        #expect(result.rows.prefix(11).map { $0.principalPercent } == [39, 40, 40, 41, 42, 42, 43, 44, 44, 45, 46])
        // Доля тела в аннуитете только растёт — инвариант, а не набор чисел.
        let shares = result.rows.map { $0.principalShare }
        #expect(zip(shares, shares.dropFirst()).allSatisfy { $0 <= $1 })
        // Последний платёж — остаток тела плюс проценты периода, поэтому доля тела 98 %, а не 100 %.
        #expect(result.rows.last?.principalPercent == 98)
    }

    @Test("Итоговая карточка: переплата 663 760 ₽ и 55,3 % от суммы кредита")
    func overpaymentSummary() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let (account, contract) = try makeReferenceLoan(context: context)
        try payFivePayments(account: account, contract: contract, context: context)

        let result = schedule(account: account, contract: contract)

        #expect(rubles(result.totalOverpayment) == 663_760)
        // 55,3 % макета: сравниваем число, а не строку — форматирование зависит от локали.
        #expect(rubles(result.overpaymentShare * 1000) == 553)
        // Переплата карточки — ровно сумма процентов показанных строк, иначе итог спорил бы с таблицей.
        #expect(result.totalOverpayment == result.rows.reduce(Decimal.zero) { $0 + $1.interest })
    }

    @Test("Ярлык месяца — «Апр 26»: три буквы с заглавной, без точки, две цифры года")
    func monthLabelMatchesMockup() throws {
        let result = LoanSchedulePresentation.make(
            terms: referenceTerms, outstandingPrincipal: 1_200_000, paymentsMade: 0,
            currency: "RUB", calendar: calendar, locale: Locale(identifier: "ru_RU")
        )

        let first = try #require(result.rows.first)
        #expect(first.date == firstPaymentDate)
        #expect(first.monthLabel.hasPrefix("Апр"))
        #expect(first.monthLabel.hasSuffix("26"))
        #expect(!first.monthLabel.contains("."))
    }

    // MARK: - Границы

    @Test("Досрочно внесённое тело пересчитывает переплату и не рвёт связь с деталкой")
    func prepaymentRecalculatesOverpayment() throws {
        let terms = referenceTerms
        let result = LoanSchedulePresentation.make(
            terms: terms, outstandingPrincipal: 937_241, paymentsMade: 5,
            currency: "RUB", calendar: calendar, locale: Locale(identifier: "ru_RU")
        )
        let detail = LoanDetailPresentation.make(
            terms: terms, outstandingPrincipal: 937_241, paymentsMade: 5,
            paidInterestTotal: 92_554, currency: "RUB", calendar: calendar
        )

        #expect(result.paymentsAhead == detail.paymentsAhead)
        // Обещание примечания карточки: при досрочном погашении переплата пересчитывается.
        #expect(result.totalOverpayment < 663_760)
        #expect(result.rows.filter { $0.isCurrent }.map { $0.index } == [6])
    }

    @Test("Закрытый кредит: все строки внесены, текущего периода нет")
    func fullyRepaidLoanHasNoCurrentRow() {
        let result = LoanSchedulePresentation.make(
            terms: referenceTerms, outstandingPrincipal: 0, paymentsMade: 60,
            currency: "RUB", calendar: calendar, locale: Locale(identifier: "ru_RU")
        )

        #expect(result.rows.count == 60)
        #expect(result.paymentsAhead == 0)
        #expect(result.rows.allSatisfy { $0.isPaid })
        #expect(result.rows.contains { $0.isCurrent } == false)
        #expect(rubles(result.totalOverpayment) == 663_760)
    }

    @Test("Без условий графика нет: пустые строки вместо выдуманных")
    func emptyTermsGiveEmptySchedule() {
        let terms = LoanTerms(
            principal: 0, annualRatePercent: 18.9, termPeriods: 0,
            firstPaymentDate: firstPaymentDate
        )
        let result = LoanSchedulePresentation.make(
            terms: terms, outstandingPrincipal: 0, paymentsMade: 0,
            currency: "RUB", calendar: calendar, locale: Locale(identifier: "ru_RU")
        )

        #expect(result.rows.isEmpty)
        #expect(result.totalOverpayment == 0)
        #expect(result.overpaymentShare == 0)
    }
}
