import Foundation
import SwiftData
import Testing
@testable import millio

/// Фаза 3: генератор interest-событий вклада — начисление против РУЧНОГО расчёта (обязательный тест
/// брифинга), идемпотентность (Т4), регенерация будущих событий при правке ставки (прошлые не трогает).
@Suite("DepositInterestScheduler")
@MainActor
struct DepositInterestSchedulerTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    // MARK: - Ручной расчёт: 1 000 000 ₽, 16% годовых, ежемесячная капитализация, 6 месяцев

    @Test
    func monthlyCapitalizationMatchesManualCalculation() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 6, to: opening)!

        let account = try service.createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 1_000_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 16, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )

        let generated = try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )
        #expect(generated == 6)

        let interestEvents = (account.events ?? [])
            .filter { $0.type == .interest }
            .sorted { $0.date < $1.date }
        #expect(interestEvents.count == 6)

        // Ручной расчёт (Decimal, .plain округление до копейки): каждый месяц rate/12 от ТЕКУЩЕГО баланса.
        let expectedMonthlyInterest: [Decimal] = [
            Decimal(string: "13333.33")!, Decimal(string: "13511.11")!, Decimal(string: "13691.26")!,
            Decimal(string: "13873.81")!, Decimal(string: "14058.79")!, Decimal(string: "14246.24")!,
        ]
        for (index, event) in interestEvents.enumerated() {
            #expect(event.amount == expectedMonthlyInterest[index])
        }

        // Decimal-литералы с плавающей запятой (82_714.54) недетерминированы (двоичное округление
        // Double при парсинге литерала) — сравниваем через `Decimal(string:)` для точного значения.
        let totalInterest = interestEvents.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }
        #expect(totalInterest == Decimal(string: "82714.54")!)

        let balanceAtTerm = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: termEnd)
        #expect(balanceAtTerm == Decimal(string: "1082714.54")!)
    }

    @Test
    func explicitPayoutDayControlsFutureScheduleAndClampsShortMonths() throws {
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 11))!
        let termEnd = calendar.date(from: DateComponents(year: 2025, month: 4, day: 30))!
        let drafts = DepositInterestScheduler.buildInitialSchedule(
            accountID: UUID(),
            meta: DepositMeta(
                rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: 31,
                allowsTopUp: false, allowsEarlyClose: true, earlyClosePenalty: 0,
                remindEnd: false, autoRollover: false
            ),
            openingBalance: 100_000,
            openingDate: opening,
            calendar: calendar
        )

        #expect(drafts.map { calendar.component(.day, from: $0.date) } == [28, 31, 30])
        #expect(drafts.map { calendar.component(.month, from: $0.date) } == [2, 3, 4])
    }

    @Test
    func nilPayoutDayPreservesOpeningDaySchedule() {
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 11))!

        let result = DepositInterestScheduler.scheduledPeriodEnd(
            openingDate: opening, months: 1, payoutDay: nil, calendar: calendar
        )

        #expect(result == calendar.date(from: DateComponents(year: 2025, month: 2, day: 11)))
    }

    // MARK: - Квартальная капитализация: сумма периодов совпадает с рынком за квартал (sanity)

    @Test
    func quarterlyCapitalizationCompoundsEveryThreeMonths() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 9, to: opening)!

        let account = try service.createAccount(
            name: "Накопительный", kind: .deposit, currency: "RUB", openingBalance: 300_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 8, capitalization: .quarterly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: true, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )

        let generated = try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )
        #expect(generated == 3) // 3, 6, 9 месяцев

        // Период 1: 300000 * 8/100/4 = 6000.00
        let events = (account.events ?? []).filter { $0.type == .interest }.sorted { $0.date < $1.date }
        #expect(events[0].amount == 6_000)
        // Период 2: 306000 * 0.02 = 6120.00
        #expect(events[1].amount == 6_120)
    }

    // MARK: - Капитализация "нет" — простые проценты одним начислением на дату окончания

    @Test
    func noCapitalizationProducesSingleSimpleInterestEvent() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))! // ровно 365 дней, не високосный

        let account = try service.createAccount(
            name: "Вклад без капитализации", kind: .deposit, currency: "RUB", openingBalance: 500_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 15, capitalization: .none, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )

        let generated = try DepositInterestScheduler.regenerateFutureInterestEvents(
            for: account, service: service, asOf: opening, calendar: calendar, context: ctx
        )
        #expect(generated == 1)

        let events = (account.events ?? []).filter { $0.type == .interest }
        #expect(events.count == 1)
        // 500 000 * 15% * 365/365 = 75 000.00
        #expect(events.first?.amount == 75_000)
    }

    // MARK: - Идемпотентность (Т4): повторный запуск не плодит дубликаты

    @Test
    func regeneratingTwiceDoesNotDuplicateEvents() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 3, to: opening)!

        let account = try service.createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )

        try DepositInterestScheduler.regenerateFutureInterestEvents(for: account, service: service, asOf: opening, calendar: calendar, context: ctx)
        try DepositInterestScheduler.regenerateFutureInterestEvents(for: account, service: service, asOf: opening, calendar: calendar, context: ctx)

        let descriptor = FetchDescriptor<AccountEvent>()
        let allEvents = try ctx.fetch(descriptor)
        let interestEvents = allEvents.filter { $0.account?.id == account.id && $0.type == .interest }
        #expect(interestEvents.count == 3) // не 6 — повторный запуск не дублирует
    }

    // MARK: - Регенерация при смене ставки: прошлые события НЕ трогает, будущие — пересчитывает

    @Test
    func regenerateAfterRateChangeKeepsPastEventsAndRecalculatesFuture() throws {
        let (container, ctx) = try makeContext()
        _ = container
        let service = AccountsCoreService(modelContext: ctx)

        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 4, to: opening)!

        let account = try service.createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 1_000_000, date: opening
        )
        account.depositMeta = DepositMeta(
            rate: 12, capitalization: .monthly, termEnd: termEnd, payoutDay: nil,
            allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
            remindEnd: false, autoRollover: false
        )
        try DepositInterestScheduler.regenerateFutureInterestEvents(for: account, service: service, asOf: opening, calendar: calendar, context: ctx)

        // "Сегодня" — конец 2-го месяца: месяцы 1 и 2 уже прошли и зафиксированы.
        let asOfMonth2 = calendar.date(byAdding: .month, value: 2, to: opening)!
        let pastEventsBefore = (account.events ?? [])
            .filter { $0.type == .interest && $0.date <= asOfMonth2 }
            .sorted { $0.date < $1.date }
        #expect(pastEventsBefore.count == 2)
        let firstMonthAmount = pastEventsBefore[0].amount

        // Владелец повышает ставку до 20% — регенерация будущих (месяцы 3, 4) от asOfMonth2.
        account.depositMeta?.rate = 20
        try DepositInterestScheduler.regenerateFutureInterestEvents(for: account, service: service, asOf: asOfMonth2, calendar: calendar, context: ctx)

        let allInterestAfter = (account.events ?? []).filter { $0.type == .interest }.sorted { $0.date < $1.date }
        #expect(allInterestAfter.count == 4) // всё те же 4 периода, не больше
        // Прошлые (месяцы 1-2) не изменились.
        #expect(allInterestAfter[0].amount == firstMonthAmount)
        #expect(allInterestAfter[1].amount == pastEventsBefore[1].amount)
        // Будущие (месяцы 3-4) пересчитаны по НОВОЙ ставке 20% — заведомо больше, чем было бы по 12%.
        let balanceAtMonth2 = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: .deposit, on: asOfMonth2)
        let expectedMonth3Interest = DepositInterestScheduler.round2(balanceAtMonth2 * 20 / 100 / 12)
        #expect(allInterestAfter[2].amount == expectedMonth3Interest)
    }
}
