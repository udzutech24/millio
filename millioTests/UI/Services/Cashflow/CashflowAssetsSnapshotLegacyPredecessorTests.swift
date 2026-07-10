import Foundation
import SwiftData
import Testing
@testable import millio

/// 6b (баг найден ночью 2026-07-11): экран Cashflow, «Активы на начало периода» = 0 для произвольного
/// периода, хотя Analytics→Динамика на тех же датах/счетах даёт корректный ненулевой Start.
///
/// Корень: `resolveAssetsSnapshotFromFinance` считал core-вклад агрегатным `accountsTotalsService.totalAt`,
/// который для мигрировавшего из легаси в core счёта возвращает 0 на датах ДО первого core-снапшота
/// (легаси-история конвертации теряется). Динамика этот случай уже решала через `legacyPredecessorContribution`.
/// Фикс: Cashflow считает core-вклад тем же per-account движком (`coreContributionWithLegacyPredecessor`).
///
/// Инвариант, который защищают эти тесты: Cashflow Start == Dynamics Start для одних дат/счетов
/// (по аналогии с `groupsAndAccountsTotalsMatch_onMixedFixture`).
@Suite("Cashflow Assets snapshot: легаси-предшественник core-счёта (баг «Активы на начало = 0»)")
@MainActor
struct CashflowAssetsSnapshotLegacyPredecessorTests {

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

    /// Total Start вкладки «Счета» Динамики для заданного (уже нормализованного) периода — эталон,
    /// с которым обязан совпасть Cashflow Assets-Start. Отдельный VM с Mock-курсами (RUB→RUB = 1.0),
    /// поэтому расхождения из-за курса исключены.
    private func dynamicsAccountsTotalStart(
        ctx: ModelContext,
        normalizedStart: Date,
        normalizedEnd: Date
    ) async throws -> Double {
        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.state.displayCurrency = "RUB"
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        // Те же ИНСТАНТЫ, что Cashflow нормализует внутри resolveAssetsSnapshotFromFinance.
        dynamicsViewModel.state.customPeriod = (start: normalizedStart, end: normalizedEnd)
        dynamicsViewModel.state.dynamicsMode = .aggregated
        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()

        let breakdown = dynamicsViewModel.state.dynamicsBreakdown
        let total = try #require(FinanceDynamicsPresentation.totalRow(from: breakdown, viewMode: .accounts))
        return total.startValue
    }

    // MARK: - Основной сценарий: период через границу миграции, Start до конвертации ≠ 0

    @Test("Мигрированный счёт, период через границу конвертации: Cashflow Start == Dynamics Start (не 0)")
    func migratedAccount_cashflowStartMatchesDynamicsStart_acrossMigrationBoundary() async throws {
        let ctx = try makeContext()
        let now = Date()
        // Счёт создан 20 дней назад, миграция 6b — 5 дней назад. Период: начало 10 дней назад (строго
        // ПОСЛЕ создания и ДО миграции — сценарий владельца), конец — сейчас.
        let createdAt = now.addingTimeInterval(-20 * 86_400)
        let migratedAt = now.addingTimeInterval(-5 * 86_400)
        let periodStart = now.addingTimeInterval(-10 * 86_400)
        let periodEnd = now

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

        // Мигратор пишет в `.shared` — тот же реестр, что читает reverse-lookup обоих путей; чистим в defer.
        let legacyUniqueID = card.cardUniqueID
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: legacyUniqueID) }
        let flagDefaults = UserDefaults(suiteName: "cashflow-pred-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt })
        #expect(migrator.migrateAll().migrated == 1)
        #expect(LegacyConversionRegistry.shared.coreAccountID(forLegacyUniqueID: legacyUniqueID) != nil)

        // Нормализация — как в resolveAssetsSnapshotFromFinance (startOfDay / endOfDay).
        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: periodStart)
        let normalizedEnd = CashflowViewModel.endOfDay(for: periodEnd, calendar: calendar)

        let dynamicsStart = try await dynamicsAccountsTotalStart(ctx: ctx, normalizedStart: normalizedStart, normalizedEnd: normalizedEnd)
        // Динамика уже даёт домиграционный баланс (~100 000), а не 0 — эталон.
        #expect(abs(dynamicsStart - 100_000) < 0.01, "Эталон Динамики: Start до конвертации = легаси-баланс (100 000), не 0")

        let cashflowViewModel = CashflowViewModel(modelContext: ctx)
        cashflowViewModel.state.displayCurrency = "RUB"
        let snapshot = try #require(
            await cashflowViewModel.resolveAssetsSnapshotFromFinance(startDate: periodStart, endDate: periodEnd),
            "resolveAssetsSnapshotFromFinance не должен возвращать nil при живом store"
        )

        // Главный инвариант бага: Cashflow Start больше НЕ 0 и совпадает с Динамикой.
        #expect(abs(snapshot.start - dynamicsStart) < 0.01,
                "Cashflow Start=\(snapshot.start) должен совпасть с Dynamics Start=\(dynamicsStart) (баг: было 0)")
        #expect(abs(snapshot.start - 100_000) < 0.01, "Cashflow Start = домиграционный легаси-баланс (100 000), а не 0")
    }

    // MARK: - Пограничный кейс: период начинается ДО существования счёта (в любом виде) → Start = 0, без падения

    @Test("Период начинается до создания счёта: Cashflow Start == Dynamics Start == 0 (наследует поведение Динамики)")
    func periodBeforeAccountExisted_cashflowStartMatchesDynamicsStart_zero() async throws {
        let ctx = try makeContext()
        let now = Date()
        // Счёт создан 5 дней назад, миграция 2 дня назад. Период начинается 20 дней назад — ДО того как
        // счёт вообще существовал (ни в легаси, ни в ядре). Ожидаем Start=0 у обоих, без падения.
        let createdAt = now.addingTimeInterval(-5 * 86_400)
        let migratedAt = now.addingTimeInterval(-2 * 86_400)
        let periodStart = now.addingTimeInterval(-20 * 86_400)
        let periodEnd = now

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
        let flagDefaults = UserDefaults(suiteName: "cashflow-pred-before-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt })
        #expect(migrator.migrateAll().migrated == 1)

        let calendar = Calendar.current
        let normalizedStart = calendar.startOfDay(for: periodStart)
        let normalizedEnd = CashflowViewModel.endOfDay(for: periodEnd, calendar: calendar)

        let dynamicsStart = try await dynamicsAccountsTotalStart(ctx: ctx, normalizedStart: normalizedStart, normalizedEnd: normalizedEnd)
        #expect(abs(dynamicsStart) < 0.01, "Динамика: до существования счёта Start = 0")

        let cashflowViewModel = CashflowViewModel(modelContext: ctx)
        cashflowViewModel.state.displayCurrency = "RUB"
        let snapshot = try #require(
            await cashflowViewModel.resolveAssetsSnapshotFromFinance(startDate: periodStart, endDate: periodEnd)
        )

        #expect(abs(snapshot.start - dynamicsStart) < 0.01,
                "Cashflow Start=\(snapshot.start) наследует поведение Динамики (0), не падает и не уходит в минус")
        #expect(abs(snapshot.start) < 0.01, "До существования счёта Cashflow Start = 0")
    }
}
