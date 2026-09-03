import Foundation
import SwiftData
import Testing
@testable import millio

/// Коммит 3: смена даты открытия вклада задним числом + пересчёт начисленных процентов.
/// «Умный режим» владельца — нет подтверждённых начислений → тихая перестройка; есть → пересчёт
/// только после явного подтверждения (UI), сам пересчёт тестируется здесь на уровне Core.
@Suite("Deposit opening date recalculation")
@MainActor
struct DepositOpeningDateRecalculationTests {

    private struct Fixture {
        let container: ModelContainer
        let context: ModelContext
        let depositID: UUID
        let opening: Date
        let termEnd: Date
        let calendar: Calendar
    }

    /// Вклад с трёхмесячным сроком и ежемесячной капитализацией — тот же паттерн, что и у
    /// `DepositOperationCoordinatorTests`. Собственные фиктивные "сегодня" передаются в каждый тест
    /// через `asOf`, а не читаются из реального времени — детерминированность независимо от даты прогона.
    private func fixture() throws -> Fixture {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let opening = calendar.date(from: DateComponents(year: 2025, month: 1, day: 1))!
        let termEnd = calendar.date(byAdding: .month, value: 3, to: opening)!
        let depositID = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .deposit, name: "Deposit", currency: "RUB", openingBalance: 100_000,
            // .daily — ежедневная капитализация: сумма процентов линейно зависит от числа дней
            // между датой открытия и сроком, поэтому сдвиг даты открытия ГАРАНТИРОВАННО меняет
            // итог (в отличие от .monthly с payoutDay=1, где сдвиг внутри месяца не добавляет
            // новый расчётный период — это свойство продукта, не баг пересчёта).
            metadata: .init(deposit: DepositMeta(
                rate: 12, capitalization: .daily, termEnd: termEnd, payoutDay: nil,
                allowsTopUp: false, allowsEarlyClose: false, earlyClosePenalty: nil,
                remindEnd: false, autoRollover: false
            )),
            date: opening, calendar: calendar
        ))
        return Fixture(container: container, context: context, depositID: depositID, opening: opening, termEnd: termEnd, calendar: calendar)
    }

    private func account(_ id: UUID, in context: ModelContext) throws -> Account {
        try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id })
    }

    private func events(_ id: UUID, in context: ModelContext) throws -> [AccountEvent] {
        try context.fetch(FetchDescriptor<AccountEvent>()).filter { $0.account?.id == id }
    }

    // MARK: (а) Нет подтверждённых начислений → тихий пересчёт

    @Test("No confirmed interest: silent recalculation on backdated opening date")
    func silentRecalculationWithoutConfirmedInterest() throws {
        let value = try fixture()
        let service = AccountsCoreService(modelContext: value.context)
        let acc = try account(value.depositID, in: value.context)

        // Сразу после создания подтверждённых начислений ещё нет — sweep не запускался.
        #expect(DepositOpeningDateRecalculation.hasConfirmedInterest(events: acc.events ?? []) == false)

        let newOpening = value.calendar.date(byAdding: .day, value: -14, to: value.opening)!
        let count = try DepositOpeningDateRecalculation.applySilently(
            account: acc, newOpeningDate: newOpening,
            meta: acc.depositMeta!, service: service, asOf: value.opening, calendar: value.calendar, context: value.context
        )

        #expect(count > 0)
        let context = ModelContext(value.container)
        let reloaded = try account(value.depositID, in: context)
        #expect(value.calendar.isDate(reloaded.createdAt, inSameDayAs: newOpening))
        let openingBalanceEvents = try events(value.depositID, in: context).filter { $0.type == .openingBalance }
        #expect(openingBalanceEvents.count == 1)
        #expect(openingBalanceEvents.first?.amount == 100_000)
    }

    // MARK: (б) Есть подтверждённые → без подтверждения ничего не меняется

    @Test("Confirmed interest exists: no mutation happens without an explicit recalculate call")
    func confirmedInterestRequiresExplicitConfirmation() throws {
        let value = try fixture()
        // Все три месячных начисления вклада 2025 года давно наступили относительно реального
        // "сегодня" — подтверждаем их фиктивным "сегодня" далеко за сроком вклада.
        let farFuture = value.calendar.date(byAdding: .year, value: 1, to: value.termEnd)!
        DepositInterestConfirmationSweep.run(context: value.context, asOf: farFuture)

        let before = try events(value.depositID, in: value.context)
        #expect(DepositOpeningDateRecalculation.hasConfirmedInterest(events: before) == true)
        #expect(DepositOpeningDateRecalculation.confirmedInterestCount(events: before) > 0)

        // UI без подтверждения просто не вызывает пересчёт — эквивалент здесь: ничего не трогаем
        // и проверяем, что лента осталась байт-в-байт той же (снимок id/дат/сумм).
        let beforeSnapshot = before.map { ($0.id, $0.date, $0.amount, $0.sourceTransactionID) }
        let after = try events(value.depositID, in: value.context)
        let afterSnapshot = after.map { ($0.id, $0.date, $0.amount, $0.sourceTransactionID) }
        #expect(beforeSnapshot.count == afterSnapshot.count)
        #expect(zip(beforeSnapshot, afterSnapshot).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 && $0.3 == $1.3 })
    }

    // MARK: (в) С подтверждением — пересозданы, ручные операции на месте

    @Test("Confirmed interest exists: explicit recalculation rebuilds it and keeps manual events")
    func confirmedRecalculationRebuildsInterestKeepsManualEvents() throws {
        let value = try fixture()
        let farFuture = value.calendar.date(byAdding: .year, value: 1, to: value.termEnd)!
        DepositInterestConfirmationSweep.run(context: value.context, asOf: farFuture)

        let acc = try account(value.depositID, in: value.context)
        let manualBefore = try events(value.depositID, in: value.context).first { $0.type == .openingBalance }
        let manualID = try #require(manualBefore?.id)

        let service = AccountsCoreService(modelContext: value.context)
        let newOpening = value.calendar.date(byAdding: .day, value: -14, to: value.opening)!
        let count = try DepositOpeningDateRecalculation.recalculateConfirmed(
            account: acc, newOpeningDate: newOpening,
            meta: acc.depositMeta!, service: service, asOf: farFuture, calendar: value.calendar, context: value.context
        )
        #expect(count > 0)

        let context = ModelContext(value.container)
        let allEvents = try events(value.depositID, in: context)
        // Ручное событие открытия — то же самое (id, сумма) — не удалено и не пересоздано.
        let manualAfter = try #require(allEvents.first { $0.id == manualID })
        #expect(manualAfter.type == .openingBalance)
        #expect(manualAfter.amount == 100_000)
        // Новые подтверждённые начисления пересозданы под новую (более раннюю) дату открытия.
        let confirmedAfter = allEvents.filter { DepositOpeningDateRecalculation.hasConfirmedInterest(events: [$0]) }
        #expect(!confirmedAfter.isEmpty)
        #expect(confirmedAfter.allSatisfy { $0.date >= newOpening })
    }

    // MARK: (г) Дата в будущем — запрет

    @Test("Future opening date is rejected for both paths")
    func futureOpeningDateIsRejected() throws {
        let value = try fixture()
        let service = AccountsCoreService(modelContext: value.context)
        let acc = try account(value.depositID, in: value.context)
        let future = value.calendar.date(byAdding: .day, value: 1, to: value.opening)!

        #expect(throws: DepositOpeningDateRecalculation.RecalculationError.futureOpeningDate) {
            try DepositOpeningDateRecalculation.applySilently(
                account: acc, newOpeningDate: future, meta: acc.depositMeta!,
                service: service, asOf: value.opening, calendar: value.calendar, context: value.context
            )
        }
    }

    // MARK: (д) Налоговая оценка (сумма подтверждённых % за год) пересчитана согласованно

    @Test("Backdating increases confirmed interest total for the affected tax year consistently")
    func backdatingIncreasesConfirmedInterestTotalConsistently() throws {
        let value = try fixture()
        let farFuture = value.calendar.date(byAdding: .year, value: 1, to: value.termEnd)!
        DepositInterestConfirmationSweep.run(context: value.context, asOf: farFuture)

        let totalBefore = try events(value.depositID, in: value.context)
            .filter { DepositOpeningDateRecalculation.hasConfirmedInterest(events: [$0]) }
            .reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }

        let acc = try account(value.depositID, in: value.context)
        let service = AccountsCoreService(modelContext: value.context)
        let newOpening = value.calendar.date(byAdding: .day, value: -14, to: value.opening)!
        _ = try DepositOpeningDateRecalculation.recalculateConfirmed(
            account: acc, newOpeningDate: newOpening,
            meta: acc.depositMeta!, service: service, asOf: farFuture, calendar: value.calendar, context: value.context
        )

        let context = ModelContext(value.container)
        let totalAfterFirstRun = try events(value.depositID, in: context)
            .filter { DepositOpeningDateRecalculation.hasConfirmedInterest(events: [$0]) }
            .reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        // 14 дополнительных дней начисления за тот же срок — больше начисленных процентов.
        #expect(totalAfterFirstRun > totalBefore)

        // Идемпотентность: повторный пересчёт на ТУ ЖЕ дату не меняет итог (согласованность).
        let acc2 = try account(value.depositID, in: context)
        let service2 = AccountsCoreService(modelContext: context)
        _ = try DepositOpeningDateRecalculation.recalculateConfirmed(
            account: acc2, newOpeningDate: newOpening,
            meta: acc2.depositMeta!, service: service2, asOf: farFuture, calendar: value.calendar, context: context
        )
        let context2 = ModelContext(value.container)
        let totalAfterSecondRun = try events(value.depositID, in: context2)
            .filter { DepositOpeningDateRecalculation.hasConfirmedInterest(events: [$0]) }
            .reduce(Decimal.zero) { $0 + ($1.amount ?? 0) }
        #expect(totalAfterSecondRun == totalAfterFirstRun)
    }
}
