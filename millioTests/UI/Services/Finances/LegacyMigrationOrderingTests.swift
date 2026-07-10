import Foundation
import SwiftData
import Testing
@testable import millio

/// Регрессия адверсариального ревью 6b Фазы 2 (2026-07-10): после перевода агрегата «Общий
/// баланс» на core-only (`FinanceTotalsService.calculateTotalsSnapshot`) порядок стал важен —
/// если `FinanceViewModel` считает тотал РАНЬШЕ, чем прошла одноразовая легаси→core миграция
/// (`LegacyAccountsMigrator`), расчёт видит core пустым и показывает «Общий баланс ≈ 0», хотя
/// легаси-данные реальны. Ни мигратор, ни конвертер не публикуют `FinanceEvent`, поэтому авто-
/// пересчёта после миграции нет — transient держится до случайного триггера или перезапуска.
///
/// Продовый фикс: `millioApp.runLegacyAccountsMigrationIfNeeded()` вызывается ДО
/// `AppLifecycleUseCase.initialize()` (который выставляет `lifecycle = .ready`), внутри
/// `onScopeResolved` в `synchronizeDataScope` — на финальном (пост-swap) контейнере, но раньше,
/// чем RootTabView/FinanceViewModel вообще монтируются и считают тотал. `millioApp.swift`
/// недоступен юнит-тестам напрямую (SwiftUI `App`), поэтому здесь порядок вызовов
/// воспроизводится напрямую (детерминированно, без ожидания фоновых Task из init — тот же
/// проверенный паттерн, что и `FinanceViewModelTests.testCalculateTotalAmountDoesNotForceRefreshRates`):
/// секция 1 документирует механизм бага (старый порядок — расчёт ДО миграции), секция 2 доказывает,
/// что фикс (новый порядок — миграция ДО расчёта) устраняет нулевой результат.
@Suite("Legacy migration ordering vs FinanceViewModel total calculation (6b Фаза 2 review fix)")
@MainActor
struct LegacyMigrationOrderingTests {

    // Контейнер должен пережить тест — `ModelContext` не держит сильную ссылку на владеющий
    // `ModelContainer`, иначе in-memory store освобождается сразу после return из makeContext()
    // (use-after-free → "crashed with signal trap"). Паттерн — как в остальных тестах этого файла
    // на AppMigrationPlan.makeInMemoryContainer (FinanceTotalsServiceFilterConsistencyTests и др.).
    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeMigrator(modelContext: ModelContext, scopeSuffix: String) -> LegacyAccountsMigrator {
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "ordering-reg-\(scopeSuffix)-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "ordering-flag-\(scopeSuffix)-\(UUID().uuidString)")!
        return LegacyAccountsMigrator(modelContext: modelContext, registry: registry, defaults: flagDefaults)
    }

    @discardableResult
    private func seedLegacyCard(_ ctx: ModelContext, balance: Double = 150_000) -> Card {
        let card = Card(name: "Легаси карта", cardNumber: "1234", cardType: .debit, balance: balance)
        ctx.insert(card)
        return card
    }

    /// Конструирует VM и детерминированно проигрывает точно ту же последовательность, что
    /// RootTabView запускает при монтировании (loadGroups/loadAccounts из init при
    /// skipInitialLoad=false реального прод-кода), но явными вызовами — без гонки с фоновым
    /// Task из init (см. FinanceViewModelTests.testCalculateTotalAmountDoesNotForceRefreshRates,
    /// тот же приём).
    private func mountAndCalculateTotal(_ ctx: ModelContext) async -> FinanceViewModel {
        let viewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)
        await viewModel.calculateTotalAmountAsync()
        return viewModel
    }

    // MARK: - Механизм бага (старый порядок: тотал считается ДО миграции)

    @Test("БАГ (документирует механизм): расчёт до миграции даёт total≈0 и НЕ восстанавливается сам после миграции")
    func totalBeforeMigration_isZeroAndDoesNotSelfHeal() async throws {
        let ctx = try makeContext()
        seedLegacyCard(ctx, balance: 150_000)
        try ctx.save()

        // Старый (баговый) порядок: тотал считается раньше, чем прошла миграция — ровно то,
        // что раньше делал RootTabView (runPostStartupRefreshes звался ПОСЛЕ .ready).
        let viewModel = await mountAndCalculateTotal(ctx)
        #expect(viewModel.state.totalAmount == 0, "До миграции core пуст — агрегат = 0 (документирует механизм бага)")

        // Миграция бежит ПОСЛЕ первого расчёта (как раньше в runPostStartupRefreshes).
        let migrator = makeMigrator(modelContext: ctx, scopeSuffix: "bug")
        let summary = migrator.migrateIfNeeded(scopeIdentifier: "test-ordering-bug")
        #expect(summary.migrated == 1)

        // Ни мигратор, ни конвертер не публикуют FinanceEvent — без явного повторного вызова
        // VM не пересчитывает тотал сам. Это и есть transient «баланс ≈ 0» до фикса.
        #expect(viewModel.state.totalAmount == 0, "Нет авто-пересчёта после миграции без явного триггера")

        // Явный повторный вызов (пользовательский триггер) чинит — иллюстрирует, что проблема
        // именно в ОТСУТСТВИИ авто-триггера, а не в самих данных/конвертере.
        await viewModel.calculateTotalAmountAsync()
        #expect(abs(viewModel.state.totalAmount - 150_000) < 0.01, "После явного пересчёта тотал корректен")
    }

    // MARK: - Фикс (новый порядок: миграция ДО расчёта тотала)

    @Test("ФИКС: миграция ДО первого расчёта тотала — total корректен сразу, без нулевого результата")
    func migrationBeforeTotal_isCorrectFromFirstCalculation() async throws {
        let ctx = try makeContext()
        seedLegacyCard(ctx, balance: 150_000)
        try ctx.save()

        // Новый продовый порядок: runLegacyAccountsMigrationIfNeeded (вызывается ДО .ready в
        // millioApp.initializeColdStart) — раньше, чем RootTabView вообще создаёт FinanceViewModel
        // и считает тотал.
        let migrator = makeMigrator(modelContext: ctx, scopeSuffix: "fix")
        let summary = migrator.migrateIfNeeded(scopeIdentifier: "test-ordering-fix")
        #expect(summary.migrated == 1)

        let viewModel = await mountAndCalculateTotal(ctx)
        #expect(abs(viewModel.state.totalAmount - 150_000) < 0.01, "Тотал должен быть корректен с первого расчёта — ни одного нулевого результата")
    }
}
