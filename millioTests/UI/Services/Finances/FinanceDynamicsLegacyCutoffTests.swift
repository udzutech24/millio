import Foundation
import SwiftData
import Testing
@testable import millio

/// Фикс двойного учёта вклада легаси-предшественника на дне миграции (план 2026-07-13).
/// `legacyPredecessorContribution` сузил окно легаси-двойника до СТРОГОЙ day-granularity границы
/// `dayKey(date) < dayKey(archivedAt)`: день миграции принадлежит core-двойнику (opening-снапшот),
/// иначе легаси + core за один день суммируются → задвоение в графике «Динамика».
/// Проверяем результирующий контракт через публичный `coreContributionWithLegacyPredecessor`
/// (единая точка, из которой считают и header/graph, и Cashflow Assets-snapshot).
@Suite("Dynamics: day-granularity cutoff легаси-предшественника (double-count fix)")
@MainActor
struct FinanceDynamicsLegacyCutoffTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            await Task.yield()
            if condition() { return }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    // MARK: - Непрерывность перехода через день миграции: без double-count

    @Test("Переход через день миграции: archivedAt-1 (легаси), archivedAt (core, НЕ сумма), archivedAt+1 (core) — тотал непрерывен")
    func migrationDayTransition_isContinuousWithoutDoubleCount() async throws {
        let ctx = try makeContext()
        let now = Date()
        // Создание 20 дней назад, миграция 5 дней назад (в полдень — чтобы ±1 день гарантированно
        // попадал в другой dayKey). Три пробные даты вокруг границы миграции.
        let createdAt = now.addingTimeInterval(-20 * 86_400)
        let cal = Calendar.current
        let migratedAt = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now.addingTimeInterval(-5 * 86_400))!
        let dayBefore = migratedAt.addingTimeInterval(-86_400) // строго ДО дня миграции → только легаси
        let dayOf = migratedAt                                 // день миграции → только core (не сумма)
        let dayAfter = migratedAt.addingTimeInterval(86_400)   // после → только core

        let card = Card(name: "Легаси карта", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = migratedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        let legacyUniqueID = card.cardUniqueID
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: legacyUniqueID) }
        let flagDefaults = UserDefaults(suiteName: "cutoff-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt })
        #expect(migrator.migrateAll().migrated == 1)
        #expect(card.archivedAt == migratedAt)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let vm = FinanceDynamicsViewModel(modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService())
        vm.handle(.loadData)
        await waitUntil { !vm.state.isLoading }

        let before = await vm.coreContributionWithLegacyPredecessor(startDate: dayBefore, endDate: dayBefore)
        let onDay = await vm.coreContributionWithLegacyPredecessor(startDate: dayOf, endDate: dayOf)
        let after = await vm.coreContributionWithLegacyPredecessor(startDate: dayAfter, endDate: dayAfter)

        // День ДО миграции: core-двойника ещё нет → вклад целиком от легаси-предшественника.
        #expect(abs(before.start - 100_000) < 0.01, "archivedAt-1: только легаси (100 000), got \(before.start)")
        // День миграции: КЛЮЧЕВОЙ кейс. До фикса легаси(100 000)+core(100 000)=200 000 → задвоение.
        // После фикса — только core (100 000).
        #expect(abs(onDay.start - 100_000) < 0.01, "archivedAt: только core, НЕ сумма/задвоение (ожидалось 100 000), got \(onDay.start)")
        // День ПОСЛЕ: только core.
        #expect(abs(after.start - 100_000) < 0.01, "archivedAt+1: только core (100 000), got \(after.start)")
    }

    // MARK: - Регрессия: обычный архивный легаси-счёт БЕЗ core-предшественника не трогается

    @Test("Регрессия: архивный легаси-счёт без миграции не даёт вклада предшественника (isLegacyActiveInTotal не тронут)")
    func archivedLegacyAccountWithoutMigration_hasNoPredecessorContribution() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-20 * 86_400)

        // Легаси-карта существует и связана с группой, но НЕ мигрирована (нет записи в реестре).
        // Такой счёт обслуживается путём isLegacyActiveInTotal (легаси-скелет), а не предшественником.
        let card = Card(name: "Обычная карта", cardNumber: "5555", cardType: .debit, currency: "RUB", balance: 50_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 50_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let vm = FinanceDynamicsViewModel(modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService())
        vm.handle(.loadData)
        await waitUntil { !vm.state.isLoading }

        // Нет core-счетов и нет записи предшественника → coreContribution = 0 (не сумма, не -50 000).
        // Фикс cutoff'а не затрагивает обычный легаси-путь.
        let contribution = await vm.coreContributionWithLegacyPredecessor(startDate: createdAt.addingTimeInterval(86_400), endDate: now)
        #expect(abs(contribution.start) < 0.01, "Немигрированный легаси-счёт не даёт core-вклада предшественника")
        #expect(abs(contribution.end) < 0.01, "Немигрированный легаси-счёт не даёт core-вклада предшественника")
    }
}
