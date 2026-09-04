import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф4 кредита: ленивый перевод старого счёта `.loan` в детальный режим (спека Р5).
///
/// Ключевое требование — односторонность: договор собирается ИЗ `LoanMeta`, но мета после этого
/// не меняется и вторым источником правды не становится (риск №1 спеки).
@Suite(.serialized)
@MainActor
struct LoanContractBackfillTests {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private var openingDate: Date {
        calendar.date(from: DateComponents(year: 2026, month: 3, day: 15))!
    }

    /// Пять платежей позади (15.04–15.08), шестой ещё впереди.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 1))!
    }

    private func makeLegacyLoan(context: ModelContext, meta: LoanMeta?) throws -> Account {
        try AccountsCoreService(modelContext: context).createAccount(
            name: "Автокредит",
            kind: .loan,
            currency: "RUB",
            openingBalance: 1_200_000,
            loanMeta: meta,
            date: openingDate
        )
    }

    private var referenceMeta: LoanMeta {
        LoanMeta(
            principal: 1_200_000,
            rate: 18.9,
            monthlyPayment: nil,
            paymentDay: 15,
            termEnd: calendar.date(from: DateComponents(year: 2031, month: 3, day: 15))!,
            scheduleType: .annuity,
            insurance: nil
        )
    }

    @Test("Счёт с легаси-метой получает договор с теми же условиями")
    func backfillSeedsContractFromLegacyMeta() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLegacyLoan(context: context, meta: referenceMeta)

        let contract = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )

        #expect(contract.principal == 1_200_000)
        #expect(contract.annualRatePercent == 18.9)
        #expect(contract.termPeriods == 60)
        #expect(contract.frequency == .monthly)
        #expect(contract.scheduleType == .annuity)
        #expect(contract.firstPaymentDate == calendar.date(from: DateComponents(year: 2026, month: 4, day: 15)))
    }

    @Test("Прогресс восстанавливается по календарю: пять платежей позади")
    func backfillRestoresProgressByCalendar() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLegacyLoan(context: context, meta: referenceMeta)

        let contract = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )

        var paidInterest = Decimal()
        var mutable = contract.paidInterestTotal
        NSDecimalRound(&paidInterest, &mutable, 0, .plain)

        #expect(contract.paymentsMade == 5)
        #expect(paidInterest == 92_554)
    }

    @Test("Легаси-мета после backfill не меняется — обратной синхронизации нет")
    func backfillDoesNotTouchLegacyMeta() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLegacyLoan(context: context, meta: referenceMeta)

        try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)

        let meta = try #require(account.loanMeta)
        #expect(meta.principal == 1_200_000)
        #expect(meta.rate == 18.9)
        #expect(meta.monthlyPayment == nil)
        #expect(meta.termEnd == calendar.date(from: DateComponents(year: 2031, month: 3, day: 15)))
    }

    @Test("Повторное открытие деталки не плодит договоров и не сбрасывает прогресс")
    func backfillIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLegacyLoan(context: context, meta: referenceMeta)

        let first = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )
        first.paymentsMade = 7
        try context.save()

        let second = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )

        #expect(second.id == first.id)
        #expect(second.paymentsMade == 7)
        #expect(try context.fetch(FetchDescriptor<LoanContract>()).count == 1)
    }

    @Test("Условий нет вообще: договор не выдумывается")
    func backfillSkipsAccountWithoutTerms() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = try makeLegacyLoan(context: context, meta: nil)

        let contract = try LoanContractBackfill.ensureContract(
            for: account, context: context, now: now, calendar: calendar
        )

        #expect(contract == nil)
        #expect(try context.fetch(FetchDescriptor<LoanContract>()).isEmpty)
    }

    @Test("Платёж из легаси-меты задаёт график: срок не выдумывается из termEnd")
    func backfillPrefersLegacyPaymentOverTermEnd() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var meta = referenceMeta
        meta.monthlyPayment = 30_929
        let account = try makeLegacyLoan(context: context, meta: meta)

        let contract = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )

        // Дата начала кредита в старом мире потеряна (миграция пишет opening датой миграции),
        // поэтому срок «до termEnd» — это остаток периодов, а principal — исходная сумма.
        // Вместе они давали платёж «по формуле» в разы больше договорного, поэтому срок не берём.
        #expect(contract.termPeriods == 0)
        #expect(contract.paymentOverride == 30_929)
        #expect(contract.principal == 1_200_000)
    }

    @Test("Ставки в легаси-мете нет: договор её не выдумывает")
    func backfillKeepsUnknownRateZero() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var meta = referenceMeta
        meta.rate = 0
        let account = try makeLegacyLoan(context: context, meta: meta)

        let contract = try #require(
            try LoanContractBackfill.ensureContract(for: account, context: context, now: now, calendar: calendar)
        )

        #expect(contract.annualRatePercent == 0)
        // И на экране такая ставка обязана выглядеть пустой, а не настоящим «0% годовых».
        #expect(LoanTermsDraft(terms: contract.terms).ratePercentText.isEmpty)
    }
}
