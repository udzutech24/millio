import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7 Gate C (2026-07-11) — `currentFinanceProductCount`/`currentTrackedTickerCount`
/// (`FinanceAddAccountView.swift`) считали ТОЛЬКО легаси-счета: у мигрированного/чисто-core
/// юзера core-счета обходили free-лимит `EntitlementPolicy.canAddFinanceProduct`/`canAddTrackedTicker`
/// (`isFinanceProductsProOnly = true` — гейтинг реально включён, не beta-заглушка). Фикс — сложение
/// `available*` (легаси, уже без архива) + `state.coreAccounts` (core, `participates(on:)`-фильтр
/// исключает архив/`includeInTotal=false` — тот же принцип). Дедуп twin-пар «по построению»:
/// конвертированный легаси архивируется мигратором → исключён из `available*`; core-двойник учтён
/// один раз через `coreAccounts`. Гейтинг (`EntitlementPolicy`) НЕ менялся — тесты вызывают его как
/// есть, проверяя, что счётчик теперь корректно его наполняет.
@Suite("FinanceAddAccountView — product/ticker counters видят core-счета (Ф5c.7 Gate C)")
@MainActor
struct FinanceAddAccountProductCounterTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        let vm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(vm)
        vm.handle(.loadGroups) // триггерит loadCoreEntities() (FinanceViewModel.swift:693)
        vm.handle(.loadAccounts)
        return vm
    }

    private func makeAddAccountView(_ vm: FinanceViewModel) -> FinanceAddAccountView {
        FinanceAddAccountView(viewModel: vm)
    }

    // MARK: - Mixed-store: легаси 3 + core 8 = 11 → лимит 10 сработал

    @Test("mixed-store: легаси 3 + core 8 = 11, лимит free (10) сработал")
    func mixedStoreProductCountHitsFreeLimit() throws {
        let ctx = try makeContext()

        // 3 активных легаси-счёта.
        let card = Card(name: "Карта", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 1_000)
        ctx.insert(card)
        ctx.insert(FinanceAccount(accountType: .card, accountID: card.cardUniqueID))
        let credit = Credit(name: "Кредит", amount: 10_000, interestRate: 5, monthlyPayment: 500, startDate: Date(), termMonths: 12, currency: "RUB")
        ctx.insert(credit)
        ctx.insert(FinanceAccount(accountType: .credit, accountID: credit.creditUniqueID))
        let investment = Investment(name: "Актив", category: .house, amount: 5_000, currency: "RUB")
        ctx.insert(investment)
        ctx.insert(FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID))

        // 8 активных core-счетов.
        let coreService = AccountsCoreService(modelContext: ctx)
        for i in 0..<8 {
            _ = try coreService.createAccount(name: "Core \(i)", kind: .debitCard, currency: "RUB", openingBalance: 100)
        }
        try ctx.save()

        let vm = makeViewModel(ctx)
        let view = makeAddAccountView(vm)

        #expect(view.currentFinanceProductCount == 11)
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: false, currentProducts: view.currentFinanceProductCount) == false, "11 >= freeFinanceProductLimit(10) — лимит обязан сработать")
    }

    // MARK: - Twin-пара: конвертированный легаси не задваивается с core-двойником

    @Test("twin-пара: мигрированный легаси-счёт считается один раз (через core), не дважды")
    func twinPairCountedOnceForProductCount() throws {
        let ctx = try makeContext()
        let now = Date()

        let card = Card(name: "Мигрированная", cardNumber: "9999", cardType: .debit, currency: "RUB", balance: 50_000)
        card.createdAt = now.addingTimeInterval(-10 * 86_400)
        card.updatedAt = now.addingTimeInterval(-3_600)
        card.initialBalance = 50_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF")
        ctx.insert(group)
        let junction = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        junction.group = group
        group.accounts = [junction]
        ctx.insert(junction)
        try ctx.save()

        let migratedAt = now.addingTimeInterval(-3_600)
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "gate-c-twin-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "gate-c-twin-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults, nowProvider: { migratedAt })
        let summary = migrator.migrateAll()
        #expect(summary.migrated == 1)
        #expect(card.archivedAt == migratedAt)

        let vm = makeViewModel(ctx)
        let view = makeAddAccountView(vm)

        #expect(view.currentFinanceProductCount == 1, "twin-пара — 1 продукт, не 2 (легаси archived исключён, core-двойник учтён один раз)")
    }

    // MARK: - Архивный core-счёт не считается

    @Test("архивный core-счёт не считается: 1 активный + 1 архивный core = 1")
    func archivedCoreAccountNotCounted() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Активный", kind: .debitCard, currency: "RUB", openingBalance: 100)
        let archived = try coreService.createAccount(name: "Архивный", kind: .debitCard, currency: "RUB", openingBalance: 200)
        try coreService.archiveAccount(archived)

        let vm = makeViewModel(ctx)
        let view = makeAddAccountView(vm)

        #expect(view.currentFinanceProductCount == 1)
    }

    // MARK: - PRO не блокируется независимо от счётчика

    @Test("PRO не блокируется при currentProducts=11 (лимит только для free)")
    func proNotBlockedDespiteOverLimit() {
        #expect(EntitlementPolicy.canAddFinanceProduct(isPro: true, currentProducts: 11) == true)
    }

    // MARK: - Ticker count: mixed-store union, паритет по акции/крипта (не облигации/металлы)

    @Test("ticker count mixed-store: легаси-акция(1) + core-крипта(1) + core-облигация(не считается) = 2")
    func tickerCountMixedStoreUnion() throws {
        let ctx = try makeContext()

        let stockInvestment = Investment(name: "Акция", category: .stocks, amount: 1_000, currency: "RUB")
        ctx.insert(stockInvestment)
        ctx.insert(FinanceAccount(accountType: .investment, accountID: stockInvestment.investmentUniqueID))

        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(
            name: "Core Crypto", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "BTC", assetClass: .crypto)
        )
        _ = try coreService.createAccount(
            name: "Core Bond", kind: .marketInvestment, currency: "USD", openingBalance: 0,
            marketMeta: MarketMeta(symbol: "OFZ", assetClass: .bond)
        )
        try ctx.save()

        let vm = makeViewModel(ctx)
        let view = makeAddAccountView(vm)

        #expect(view.currentTrackedTickerCount == 2, "акция(легаси)+крипта(core) считаются, облигация(core) — нет (паритет с isMarketTickerCategory)")
    }

    @Test("ticker twin-пара: мигрированная акция считается один раз через core-двойник")
    func tickerTwinPairCountedOnce() throws {
        let ctx = try makeContext()
        let now = Date()

        let stockInvestment = Investment(name: "Акция", investmentType: .positive, category: .stocks, amount: 1_000, currency: "RUB")
        stockInvestment.createdAt = now.addingTimeInterval(-10 * 86_400)
        stockInvestment.updatedAt = now.addingTimeInterval(-3_600)
        ctx.insert(stockInvestment)
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF")
        ctx.insert(group)
        let junction = FinanceAccount(accountType: .investment, accountID: stockInvestment.investmentUniqueID)
        junction.group = group
        group.accounts = [junction]
        ctx.insert(junction)
        try ctx.save()

        let migratedAt = now.addingTimeInterval(-3_600)
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "gate-c-ticker-twin-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "gate-c-ticker-twin-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults, nowProvider: { migratedAt })
        let summary = migrator.migrateAll()
        #expect(summary.migrated == 1)

        let vm = makeViewModel(ctx)
        let view = makeAddAccountView(vm)

        #expect(view.currentTrackedTickerCount <= 1, "twin-пара — максимум 1 тикер, не 2 (легаси archived исключён из availableInvestments)")
    }
}
