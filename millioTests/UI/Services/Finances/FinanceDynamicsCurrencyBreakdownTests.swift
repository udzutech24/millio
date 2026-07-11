import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7 Gate A (2026-07-11) — `FinanceDynamicsViewModel.updateCurrencyBreakdown()` игнорировал
/// core-счета (только `getAccountsForCalculation()→[FinanceAccount]` + легаси-кэши): у мигрированного
/// юзера core-счета (вклады/кредиты/маркет-инвестиции, созданные через `AccountsCoreService`)
/// давали 0 в разбивке «Динамики» по валютам. Характеризация ДО фикса + red-до/green-после mixed-store
/// (Fable-риск №5) + дедуп-регресс на реальной паре легаси-двойник↔core.
///
/// [Fable-ревизия] Дедуп держится на БЕЗУСЛОВНОМ `archivedAt == nil`-гарде внутри
/// `FinanceNetWorthSignedAmount.signedValue` (card/credit/investment — каждый), не на
/// scope-фильтре `.currentVisible`/`state.showArchivedAccounts`: мигрированный легаси-двойник
/// не попадает в `nativeTotals` НИ ПРИ КАКОМ состоянии тумблера «показать архивные». Изначальная
/// версия фикса добавляла доп. проверку через `LegacyConversionRegistry` — мутационный тест
/// (отключение проверки) показал, что она НИКОГДА не исполняется (dead code), убрана.
@Suite("FDVM.updateCurrencyBreakdown — core-счета видны, без задвоения (Ф5c.7 Gate A)")
@MainActor
struct FinanceDynamicsCurrencyBreakdownTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
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

    private func makeDynamicsVM(_ ctx: ModelContext) async -> FinanceDynamicsViewModel {
        let fvm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(fvm)
        fvm.handle(.loadGroups)
        fvm.handle(.loadAccounts)

        let dvm = FinanceDynamicsViewModel(modelContext: ctx, financeViewModel: fvm, currencyService: MockCurrencyRateService())
        Self.retained.append(dvm)
        dvm.handle(.loadData)
        await waitUntil { !dvm.state.isLoading }
        return dvm
    }

    // MARK: - Характеризация ДО фикса: легаси-only не регрессирует

    /// Легаси-only сценарий (нет core-счетов) — поведение фикс не меняет: остаётся 100% RUB=12000.
    @Test("characterization: легаси-only разбивка = RUB 12000 (100%), core не влияет")
    func legacyOnlyCurrencyBreakdown() async throws {
        let ctx = try makeContext()
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF")
        ctx.insert(group)
        let card = Card(name: "A", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 12_000)
        card.includeInTotal = true
        ctx.insert(card)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = group
        ctx.insert(junction)
        try ctx.save()

        let dvm = await makeDynamicsVM(ctx)
        await dvm.updateCurrencyBreakdown()

        #expect(dvm.state.currencyBreakdown.count == 1)
        #expect(dvm.state.currencyBreakdown.first?.currency == "RUB")
        #expect(abs((dvm.state.currencyBreakdown.first?.convertedValue ?? 0) - 12_000) < 0.01)
    }

    // MARK: - Mixed-store: ДО фикса красный (core=0 невидим), ПОСЛЕ фикса зелёный (17000)

    /// Тот же mixed-store фикстур-анкер, что `FinanceViewModelCharacterizationTests.mixedStoreGroupTotal`
    /// (легаси 10000 + core 7000 = 17000, group "Микс"). ДО фикса это давало бы 10000 (core невидим) —
    /// TDD-ожидание ПРАВИЛЬНОГО поведения.
    @Test("mixed-store: разбивка = RUB 17000 (легаси 10000 + core 7000), core-хвост виден")
    func mixedStoreCurrencyBreakdownIncludesCoreTail() async throws {
        let ctx = try makeContext()

        let legacyGroup = FinanceGroup(name: "Микс", colorHex: "#123456")
        ctx.insert(legacyGroup)
        let legacyCard = Card(name: "Легаси", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        legacyCard.includeInTotal = true
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = legacyGroup
        ctx.insert(junction)

        let coreGroup = AccountGroup(name: "Микс")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Core", kind: .debitCard, currency: "RUB", openingBalance: 7_000, group: coreGroup)
        try ctx.save()

        let dvm = await makeDynamicsVM(ctx)
        await dvm.updateCurrencyBreakdown()

        #expect(dvm.state.currencyBreakdown.count == 1)
        #expect(dvm.state.currencyBreakdown.first?.currency == "RUB")
        #expect(abs((dvm.state.currencyBreakdown.first?.convertedValue ?? 0) - 17_000) < 0.01, "core-вклад (7000) обязан попасть в разбивку по валютам")
    }

    // MARK: - Дедуп: реальная пара легаси-двойник↔core не считается дважды

    /// Легаси-карта мигрирована в core (`LegacyAccountsMigrator`) — легаси archived, core-двойник
    /// живой. Разбивка обязана показать баланс РОВНО ОДИН РАЗ (100000), не дважды (200000).
    @Test("дедуп: мигрированный легаси-двойник не задваивается с core-счётом")
    func migratedTwinNotDoubleCounted() async throws {
        let ctx = try makeContext()
        let now = Date()

        let card = Card(name: "Мигрированная", cardNumber: "4321", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = now.addingTimeInterval(-10 * 86_400)
        card.updatedAt = now.addingTimeInterval(-3_600)
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

        let migratedAt = now.addingTimeInterval(-3_600)
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "currency-breakdown-dedup-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "currency-breakdown-dedup-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults, nowProvider: { migratedAt })
        let summary = migrator.migrateAll()
        #expect(summary.migrated == 1)
        #expect(card.archivedAt == migratedAt)

        let dvm = await makeDynamicsVM(ctx)
        await dvm.updateCurrencyBreakdown()

        #expect(dvm.state.currencyBreakdown.count == 1)
        #expect(abs((dvm.state.currencyBreakdown.first?.convertedValue ?? 0) - 100_000) < 0.01, "мигрированный легаси-двойник не должен задваиваться с core-счётом")
    }

    /// [Fable-фикс] Тот же twin-сценарий, но с `showArchivedAccounts == true` (легаси-двойник ВИДЕН
    /// в `.currentVisible`, `isAccountArchived`-scope-фильтр обойдён). Мутационно доказано (см. журнал
    /// Gate A): дедуп держится НЕ на реестре конверсии, а на безусловном `archivedAt == nil`-гарде
    /// внутри `FinanceNetWorthSignedAmount.signedValue` — он нуль-ит архивный легаси-счёт независимо
    /// от тумблера. Никакой доп. инъекции registry не нужно — тест проверяет РЕАЛЬНЫЙ прод-путь как есть.
    @Test("дедуп при showArchivedAccounts=true: разбивка = 100000, не задвоена")
    func migratedTwinNotDoubleCountedWhenArchivedAccountsShown() async throws {
        let ctx = try makeContext()
        let now = Date()

        let card = Card(name: "Мигрированная", cardNumber: "4321", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = now.addingTimeInterval(-10 * 86_400)
        card.updatedAt = now.addingTimeInterval(-3_600)
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

        let migratedAt = now.addingTimeInterval(-3_600)
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "currency-breakdown-dedup-archived-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "currency-breakdown-dedup-archived-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults, nowProvider: { migratedAt })
        let summary = migrator.migrateAll()
        #expect(summary.migrated == 1)
        #expect(card.archivedAt == migratedAt)

        let dvm = await makeDynamicsVM(ctx)
        dvm.state.showArchivedAccounts = true

        await dvm.updateCurrencyBreakdown()

        #expect(dvm.state.currencyBreakdown.count == 1)
        #expect(abs((dvm.state.currencyBreakdown.first?.convertedValue ?? 0) - 100_000) < 0.01, "showArchivedAccounts=true не должен задваивать легаси-двойник с core-счётом")
    }
}
