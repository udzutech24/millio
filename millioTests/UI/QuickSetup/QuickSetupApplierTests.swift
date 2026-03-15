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
            CashflowCustomCategory.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func testApplyCreatesSelectedGroupsAndAssignsProductsToThem() throws {
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
}
