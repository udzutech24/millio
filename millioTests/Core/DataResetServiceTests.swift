import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct DataResetServiceTests {
    private func makeContainer() -> ModelContainer {
        let schema = Schema([
            Item.self,
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            CashflowCustomCategory.self,
            CashflowSystemCategoryOverride.self,
            Cashback.self,
            CashbackCustomCategory.self,
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    private func makeIsolatedSettingsManager() -> (manager: SettingsManager, cleanup: () -> Void) {
        let suiteName = "DataResetServiceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = SettingsManager(defaults: defaults)
        let cleanup = {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (manager, cleanup)
    }

    @Test("Операции удаляются только в выбранном периоде")
    func testPeriodOperationsDeletion() throws {
        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            clearPinCode: {},
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let recent = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: Calendar.current.date(byAdding: .day, value: -5, to: Date()) ?? Date()
        )
        let old = CashflowTransaction(
            transactionType: .expense,
            amount: 200,
            currency: "RUB",
            transactionDate: Calendar.current.date(byAdding: .day, value: -70, to: Date()) ?? Date()
        )
        context.insert(recent)
        context.insert(old)
        try context.save()

        _ = try service.execute(
            DataResetRequest(
                period: DataResetPeriod(
                    preset: .last30Days,
                    customStartDate: Date(),
                    customEndDate: Date()
                ),
                targets: [.operations]
            )
        )

        let remaining = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.amount == 200)
    }

    @Test("Очистка счетов удаляет связанные транзакции, кешбэк и связи")
    func testAccountsCleanupDeletesDependencies() throws {
        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            clearPinCode: {},
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF", order: 0)
        let card = Card(name: "Карта", cardNumber: "1234", currency: "RUB", balance: 1500)
        let link = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        link.group = group
        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 300,
            currency: "RUB",
            transactionDate: Date(),
            cardID: card.cardUniqueID
        )
        let cashback = Cashback(
            name: "Тест",
            category: .other,
            percentage: 5,
            cardIDs: [card.cardUniqueID],
            monthKey: Cashback.monthKey(for: Date())
        )

        context.insert(group)
        context.insert(card)
        context.insert(link)
        context.insert(transaction)
        context.insert(cashback)
        try context.save()

        let result = try service.execute(
            DataResetRequest(period: .allTime(), targets: [.accounts])
        )

        #expect(result.deletedCards == 1)
        #expect(result.deletedFinanceAccounts == 1)
        #expect(result.deletedFinanceGroups == 1)
        #expect(result.deletedTransactions == 1)
        #expect(result.deletedCashbacks == 1)

        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FinanceAccount>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<FinanceGroup>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Cashback>()).isEmpty)
    }

    @Test("Операции по счетам удаляются по периоду, счета остаются")
    func testAccountOperationsDeletionKeepsAccounts() throws {
        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            clearPinCode: {},
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let card = Card(name: "Карта", cardNumber: "9999", currency: "RUB", balance: 1000)
        context.insert(card)

        let recentLinked = CashflowTransaction(
            transactionType: .expense,
            amount: 150,
            currency: "RUB",
            transactionDate: Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date(),
            cardID: card.cardUniqueID
        )
        let oldLinked = CashflowTransaction(
            transactionType: .expense,
            amount: 250,
            currency: "RUB",
            transactionDate: Calendar.current.date(byAdding: .day, value: -50, to: Date()) ?? Date(),
            cardID: card.cardUniqueID
        )
        let recentUnlinked = CashflowTransaction(
            transactionType: .income,
            amount: 700,
            currency: "RUB",
            transactionDate: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        )
        context.insert(recentLinked)
        context.insert(oldLinked)
        context.insert(recentUnlinked)
        try context.save()

        let result = try service.execute(
            DataResetRequest(
                period: DataResetPeriod(
                    preset: .last30Days,
                    customStartDate: Date(),
                    customEndDate: Date()
                ),
                targets: [.accountOperations]
            )
        )

        #expect(result.deletedTransactions == 1)
        #expect(try context.fetch(FetchDescriptor<Card>()).count == 1)

        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(transactions.count == 2)
        #expect(transactions.contains(where: { $0.amount == 250 }))
        #expect(transactions.contains(where: { $0.amount == 700 }))
    }

    @Test("Очистка категорий мигрирует custom-значения в safe fallback и удаляет пользовательские категории")
    func testCategoriesResetMigratesAndDeletes() throws {
        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            clearPinCode: {},
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let customCashflowCategory = CashflowCustomCategory(kind: .expense, name: "Хобби", icon: "🎯")
        let systemOverride = CashflowSystemCategoryOverride(
            kind: .expense,
            categoryRaw: ExpenseCategory.shopping.rawValue,
            name: "Шопинг+",
            icon: "🛍️"
        )
        let customCashbackCategory = CashbackCustomCategory(name: "Кафе+", icon: "☕️")

        let transaction = CashflowTransaction(
            transactionType: .expense,
            amount: 100,
            currency: "RUB",
            transactionDate: Date(),
            expenseCategoryRaw: "\(CashflowTransaction.customCategoryPrefix)\(customCashflowCategory.categoryID)"
        )
        let cashback = Cashback(
            name: "Кастом",
            categoryRaw: "\(Cashback.customCategoryPrefix)\(customCashbackCategory.categoryID)",
            percentage: 7,
            cardIDs: [],
            monthKey: Cashback.monthKey(for: Date())
        )

        context.insert(customCashflowCategory)
        context.insert(systemOverride)
        context.insert(customCashbackCategory)
        context.insert(transaction)
        context.insert(cashback)
        try context.save()

        let result = try service.execute(
            DataResetRequest(period: .allTime(), targets: [.categories])
        )

        #expect(result.deletedCashflowCustomCategories == 1)
        #expect(result.deletedCashflowSystemOverrides == 1)
        #expect(result.deletedCashbackCustomCategories == 1)

        let remainingTransactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(remainingTransactions.count == 1)
        #expect(remainingTransactions[0].expenseCategoryRaw == ExpenseCategory.other.rawValue)

        let remainingCashbacks = try context.fetch(FetchDescriptor<Cashback>())
        #expect(remainingCashbacks.count == 1)
        #expect(remainingCashbacks[0].categoryRaw == CashbackCategory.other.rawValue)

        #expect(try context.fetch(FetchDescriptor<CashflowCustomCategory>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CashflowSystemCategoryOverride>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<CashbackCustomCategory>()).isEmpty)
    }

    @Test("Обнуление счетов в периоде оставляет счета и создает корректирующие операции")
    func testZeroAccountsInPeriodKeepsAccountsAndCreatesAdjustments() throws {
        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            clearPinCode: {},
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let card = Card(name: "Карта", cardNumber: "1234", currency: "RUB", balance: 500)
        let credit = Credit(
            name: "Кредит",
            amount: 10000,
            interestRate: 0,
            monthlyPayment: 1000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB"
        )
        credit.remainingAmount = 4200
        let investment = Investment(
            name: "Актив",
            investmentType: .positive,
            category: .other,
            amount: 800,
            currency: "RUB"
        )

        context.insert(card)
        context.insert(credit)
        context.insert(investment)
        try context.save()

        let result = try service.execute(
            DataResetRequest(
                period: DataResetPeriod(
                    preset: .custom,
                    customStartDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? Date(),
                    customEndDate: Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 28)) ?? Date()
                ),
                targets: [.zeroAccountsInPeriod]
            )
        )

        #expect(result.zeroedCards == 1)
        #expect(result.zeroedCredits == 1)
        #expect(result.zeroedInvestments == 1)
        #expect(result.createdAdjustmentTransactions == 6)

        let cards = try context.fetch(FetchDescriptor<Card>())
        let credits = try context.fetch(FetchDescriptor<Credit>())
        let investments = try context.fetch(FetchDescriptor<Investment>())
        #expect(cards.count == 1)
        #expect(credits.count == 1)
        #expect(investments.count == 1)
        #expect(abs(cards[0].balance - 500) < 0.01)
        #expect(abs(credits[0].remainingAmount - 4200) < 0.01)
        #expect(abs(investments[0].amount - 800) < 0.01)

        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(transactions.count == 6)
        #expect(transactions.contains(where: { $0.note?.contains("(end)") == true }))
        #expect(transactions.contains(where: { $0.note?.contains("(restore)") == true }))
    }

    @Test("Очистка настроек возвращает дефолты и обновляет appState")
    func testSettingsReset() throws {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        let container = makeContainer()
        let context = container.mainContext
        let appState = AppState()

        isolated.manager.isBackupEnabled = true
        isolated.manager.isEncryptionEnabled = true
        isolated.manager.isDailyReminderEnabled = true
        isolated.manager.isAppLockEnabled = true
        isolated.manager.isBiometricUnlockEnabled = true
        isolated.manager.profileDisplayName = "Alex"
        isolated.manager.primaryCurrencyCode = "USD"
        isolated.manager.favoriteCurrencyCodes = ["EUR", "KZT"]

        appState.isBackupEnabled = true
        appState.isDailyReminderEnabled = true
        appState.isAppLockEnabled = true
        appState.isBiometricUnlockEnabled = true
        appState.profileDisplayName = "Alex"
        appState.primaryCurrencyCode = "USD"

        var didClearPin = false
        let service = DataResetService(
            modelContext: context,
            appState: appState,
            settingsManager: isolated.manager,
            clearPinCode: { didClearPin = true },
            disableDailyReminder: {},
            publishEvent: { _ in }
        )

        let result = try service.execute(
            DataResetRequest(period: .allTime(), targets: [.settings])
        )

        #expect(result.settingsReset == true)
        #expect(didClearPin == true)

        #expect(isolated.manager.isBackupEnabled == false)
        #expect(isolated.manager.isEncryptionEnabled == false)
        #expect(isolated.manager.isDailyReminderEnabled == false)
        #expect(isolated.manager.isAppLockEnabled == false)
        #expect(isolated.manager.isBiometricUnlockEnabled == false)
        #expect(isolated.manager.primaryCurrencyCode == SettingsManager.defaultPrimaryCurrencyCode)

        #expect(appState.isBackupEnabled == false)
        #expect(appState.isDailyReminderEnabled == false)
        #expect(appState.isAppLockEnabled == false)
        #expect(appState.isBiometricUnlockEnabled == false)
        #expect(appState.isAppLocked == false)
        #expect(appState.primaryCurrencyCode == SettingsManager.defaultPrimaryCurrencyCode)
    }
}
