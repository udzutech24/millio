import XCTest
import SwiftData
@testable import millio

@MainActor
final class QuickSetupApplierTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowSystemCategoryOverride.self,
            CashflowCustomCategory.self,
            CashbackCustomCategory.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testApplyCreatesSelectedGroupsAndAssignsProductsToThem() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        appState.subscriptionAccessSource = .subscription
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let previousQuickSetupCompleted = SettingsManager.shared.isQuickSetupCompleted
        let previousBannerHidden = SettingsManager.shared.isQuickSetupBannerHidden
        let previousFavoriteCurrencies = SettingsManager.shared.favoriteCurrencyCodes
        let previousQuickSetupCategories = SettingsManager.shared.quickSetupExpenseCategoryIDs
        let previousBackupEnabled = SettingsManager.shared.isBackupEnabled
        defer {
            SettingsManager.shared.isQuickSetupCompleted = previousQuickSetupCompleted
            SettingsManager.shared.isQuickSetupBannerHidden = previousBannerHidden
            SettingsManager.shared.favoriteCurrencyCodes = previousFavoriteCurrencies
            SettingsManager.shared.quickSetupExpenseCategoryIDs = previousQuickSetupCategories
            SettingsManager.shared.isBackupEnabled = previousBackupEnabled
        }

        let locale = Locale(identifier: "ru_RU")
        let group = QuickSetupGroupPreset.all[0].draft(for: locale)
        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [ExpenseCategory.other.rawValue],
            groups: [group],
            products: [
                QuickSetupProductDraft(
                    type: .card,
                    name: "Основная карта",
                    amount: 1500,
                    currencyCode: "RUB",
                    groupDraftID: group.id,
                    visualIcon: QuickSetupProductType.card.icon
                )
            ],
            backupPreference: .localOnly
        )

        try applier.apply(selection)

        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        XCTAssertEqual(groups.map(\.name), [group.name])

        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts.first?.group?.name, group.name)

        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.name, "Основная карта")
    }

    func testApplyFallsBackToUngroupedWhenProductHasNoGroup() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let previousQuickSetupCompleted = SettingsManager.shared.isQuickSetupCompleted
        let previousBannerHidden = SettingsManager.shared.isQuickSetupBannerHidden
        let previousFavoriteCurrencies = SettingsManager.shared.favoriteCurrencyCodes
        let previousQuickSetupCategories = SettingsManager.shared.quickSetupExpenseCategoryIDs
        let previousBackupEnabled = SettingsManager.shared.isBackupEnabled
        defer {
            SettingsManager.shared.isQuickSetupCompleted = previousQuickSetupCompleted
            SettingsManager.shared.isQuickSetupBannerHidden = previousBannerHidden
            SettingsManager.shared.favoriteCurrencyCodes = previousFavoriteCurrencies
            SettingsManager.shared.quickSetupExpenseCategoryIDs = previousQuickSetupCategories
            SettingsManager.shared.isBackupEnabled = previousBackupEnabled
        }

        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [ExpenseCategory.other.rawValue],
            groups: [],
            products: [
                QuickSetupProductDraft(
                    type: .card,
                    name: "Резервная карта",
                    amount: 300,
                    currencyCode: "RUB",
                    visualIcon: QuickSetupProductType.card.icon
                )
            ],
            backupPreference: .localOnly
        )

        try applier.apply(selection)

        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, FinanceSystemGroups.ungroupedName)

        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        XCTAssertEqual(accounts.first?.group?.name, FinanceSystemGroups.ungroupedName)
    }

    func testApplyExpenseCategoriesDoesNotModifyCashbackCategories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let cashbackCategory = CashbackCustomCategory(name: "Базовый кешбэк", icon: "⭐️")
        context.insert(cashbackCategory)
        try context.save()

        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [
                ExpenseCategory.groceries.rawValue,
                ExpenseCategory.transport.rawValue,
                ExpenseCategory.other.rawValue
            ],
            groups: [],
            products: [],
            backupPreference: .localOnly
        )

        try applier.apply(selection)

        let cashbackCategories = try context.fetch(FetchDescriptor<CashbackCustomCategory>())
        XCTAssertEqual(cashbackCategories.count, 1)
        XCTAssertEqual(cashbackCategories.first?.name, "Базовый кешбэк")
    }

    func testApplyCreatesRealEntitiesForEverySupportedProductType() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        appState.subscriptionAccessSource = .subscription
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let locale = Locale(identifier: "ru_RU")
        let group = QuickSetupGroupPreset.all[0].draft(for: locale)
        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [ExpenseCategory.other.rawValue],
            groups: [group],
            products: [
                QuickSetupProductDraft(
                    type: .card,
                    name: "Карта",
                    amount: 1200,
                    currencyCode: "RUB",
                    groupDraftID: group.id,
                    visualIcon: QuickSetupProductType.card.icon
                ),
                QuickSetupProductDraft(
                    type: .realEstate,
                    name: "Квартира",
                    amount: 5_000_000,
                    currencyCode: "RUB",
                    groupDraftID: group.id,
                    visualIcon: QuickSetupProductType.realEstate.icon
                ),
                QuickSetupProductDraft(
                    type: .debt,
                    name: "Долг другу",
                    amount: 15_000,
                    currencyCode: "RUB",
                    groupDraftID: group.id,
                    visualIcon: QuickSetupProductType.debt.icon
                ),
                QuickSetupProductDraft(
                    type: .credit,
                    name: "Кредит",
                    amount: 300_000,
                    currencyCode: "RUB",
                    groupDraftID: group.id,
                    visualIcon: QuickSetupProductType.credit.icon
                ),
                QuickSetupProductDraft(
                    type: .ticker,
                    name: "AAPL",
                    amount: 300,
                    currencyCode: "USD",
                    groupDraftID: group.id,
                    marketSnapshot: QuickSetupProductMarketSnapshot(
                        symbol: "AAPL",
                        exchange: "NASDAQ",
                        currencyCode: "USD",
                        quantity: 2,
                        purchaseUnitPrice: 150,
                        currentUnitPrice: 160,
                        priceUpdatedAt: Date(),
                        providerRaw: "market-backend"
                    ),
                    visualIcon: QuickSetupProductType.ticker.icon
                ),
                QuickSetupProductDraft(
                    type: .crypto,
                    name: "BTC/USD",
                    amount: 200_000,
                    currencyCode: "USD",
                    groupDraftID: group.id,
                    marketSnapshot: QuickSetupProductMarketSnapshot(
                        symbol: "BTC/USD",
                        exchange: "BINANCE",
                        currencyCode: "USD",
                        quantity: 0.5,
                        purchaseUnitPrice: 400_000,
                        currentUnitPrice: 420_000,
                        priceUpdatedAt: Date(),
                        providerRaw: "market-backend"
                    ),
                    visualIcon: QuickSetupProductType.crypto.icon
                )
            ],
            backupPreference: .localOnly
        )

        try applier.apply(selection)

        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.name, group.name)

        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        XCTAssertEqual(accounts.count, 6)
        XCTAssertTrue(accounts.allSatisfy { $0.group?.name == group.name })

        let cards = try context.fetch(FetchDescriptor<Card>())
        XCTAssertEqual(cards.count, 1)
        XCTAssertEqual(cards.first?.name, "Карта")
        XCTAssertEqual(cards.first?.balance, 1200)

        let credits = try context.fetch(FetchDescriptor<Credit>())
        XCTAssertEqual(credits.count, 1)
        XCTAssertEqual(credits.first?.name, "Кредит")
        XCTAssertEqual(credits.first?.amount, 300_000)

        let investments = try context.fetch(FetchDescriptor<Investment>())
        XCTAssertEqual(investments.count, 4)
        XCTAssertNotNil(investments.first(where: { $0.name == "Квартира" && $0.category == .house }))
        XCTAssertNotNil(investments.first(where: { $0.name == "Долг другу" && $0.category == .debt }))

        let stock = try XCTUnwrap(investments.first(where: { $0.marketSymbol == "AAPL" }))
        XCTAssertEqual(stock.category, .stocks)
        XCTAssertEqual(stock.marketQuantity, 2)
        XCTAssertEqual(stock.averagePurchaseUnitPrice, 150)
        XCTAssertEqual(stock.lastKnownUnitPrice, 160)

        let crypto = try XCTUnwrap(investments.first(where: { $0.marketSymbol == "BTC/USD" }))
        XCTAssertEqual(crypto.category, .crypto)
        XCTAssertEqual(crypto.marketQuantity, 0.5)
        XCTAssertEqual(crypto.averagePurchaseUnitPrice, 400_000)
        XCTAssertEqual(crypto.lastKnownUnitPrice, 420_000)
    }

    func testApplyFreeQuickSetupRejectsSecondTicker() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        appState.subscriptionAccessSource = .free
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [ExpenseCategory.other.rawValue],
            groups: [],
            products: [
                QuickSetupProductDraft(
                    type: .ticker,
                    name: "AAPL",
                    amount: 100,
                    currencyCode: "USD",
                    marketSnapshot: QuickSetupProductMarketSnapshot(
                        symbol: "AAPL",
                        exchange: "NASDAQ",
                        currencyCode: "USD",
                        quantity: 1,
                        purchaseUnitPrice: 100,
                        currentUnitPrice: 100,
                        priceUpdatedAt: nil,
                        providerRaw: nil
                    ),
                    visualIcon: QuickSetupProductType.ticker.icon
                ),
                QuickSetupProductDraft(
                    type: .ticker,
                    name: "MSFT",
                    amount: 200,
                    currencyCode: "USD",
                    marketSnapshot: QuickSetupProductMarketSnapshot(
                        symbol: "MSFT",
                        exchange: "NASDAQ",
                        currencyCode: "USD",
                        quantity: 1,
                        purchaseUnitPrice: 200,
                        currentUnitPrice: 200,
                        priceUpdatedAt: nil,
                        providerRaw: nil
                    ),
                    visualIcon: QuickSetupProductType.ticker.icon
                )
            ],
            backupPreference: .localOnly
        )

        XCTAssertThrowsError(try applier.apply(selection)) { error in
            XCTAssertEqual(error.localizedDescription, "В быстрой настройке без PRO доступна 1 акция")
        }
    }

    func testApplyFreeQuickSetupRejectsCrypto() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        appState.subscriptionAccessSource = .free
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [ExpenseCategory.other.rawValue],
            groups: [],
            products: [
                QuickSetupProductDraft(
                    type: .crypto,
                    name: "BTC/USD",
                    amount: 200_000,
                    currencyCode: "USD",
                    marketSnapshot: QuickSetupProductMarketSnapshot(
                        symbol: "BTC/USD",
                        exchange: "BINANCE",
                        currencyCode: "USD",
                        quantity: 0.5,
                        purchaseUnitPrice: 400_000,
                        currentUnitPrice: 420_000,
                        priceUpdatedAt: nil,
                        providerRaw: nil
                    ),
                    visualIcon: QuickSetupProductType.crypto.icon
                )
            ],
            backupPreference: .localOnly
        )

        XCTAssertThrowsError(try applier.apply(selection)) { error in
            XCTAssertEqual(error.localizedDescription, "Криптовалюта доступна в PRO")
        }
    }

    func testApplyExpenseCategoriesPersistsVisibilityForExpandedSystemCategories() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let applier = QuickSetupApplier(modelContext: context, appState: appState)

        let locale = Locale(identifier: "ru_RU")
        let presets = QuickSetupExpenseCategoryPreset.all(for: locale)
        let travel = try XCTUnwrap(presets.first(where: { $0.id == ExpenseCategory.travel.rawValue }))

        let selection = QuickSetupSelection(
            language: .russian,
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: ["USD"],
            selectedExpenseCategoryIDs: [
                ExpenseCategory.groceries.rawValue,
                ExpenseCategory.transport.rawValue,
                travel.id
            ],
            groups: [],
            products: [],
            backupPreference: .localOnly
        )

        try applier.apply(selection)

        XCTAssertEqual(
            Set(SettingsManager.shared.quickSetupExpenseCategoryIDs),
            Set(selection.selectedExpenseCategoryIDs)
        )

        let overrides = try context.fetch(FetchDescriptor<CashflowSystemCategoryOverride>())
        let groceriesOverride = overrides.first(where: { $0.categoryRaw == ExpenseCategory.groceries.rawValue })
        XCTAssertTrue(groceriesOverride == nil || groceriesOverride?.isHidden == false)

        let cafeOverride = try XCTUnwrap(overrides.first(where: { $0.categoryRaw == ExpenseCategory.cafe.rawValue }))
        XCTAssertTrue(cafeOverride.isHidden)

        let otherOverride = overrides.first(where: { $0.categoryRaw == ExpenseCategory.other.rawValue })
        XCTAssertTrue(otherOverride == nil || otherOverride?.isHidden == false)

        let customCategories = try context.fetch(FetchDescriptor<CashflowCustomCategory>())
        XCTAssertTrue(customCategories.isEmpty)
    }
}
