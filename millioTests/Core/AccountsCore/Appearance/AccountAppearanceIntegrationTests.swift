import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф0 V11: оформление счёта переживает backup→wipe→restore, сироты подчищаются, а «избранное»
/// core-счёта доходит до Cashflow-пикера ПУТЁМ СОЗДАНИЯ (VM → фабрика опций), а не только
/// через трансформацию — урок `millio-integration-test-creation-path`.
@Suite(.serialized)
@MainActor
struct AccountAppearanceIntegrationTests {

    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CurrencyFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    @Test("backup → wipe → restore: оформление и isFavorite восстанавливаются")
    func appearanceSurvivesBackupRoundtrip() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let account = Account(name: "Основной", kind: .cash)
            context.insert(account)
            let store = AccountAppearanceStore(context: context)
            try store.upsert(accountID: account.id) {
                $0.isFavorite = true
                $0.tintHex = "#21A038"
                $0.presetRaw = "gradient.emerald"
                $0.iconName = "monogram:ОС"
            }
            let bareID = account.id
            try context.save()

            let backupData = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).isEmpty)

            try repository.importAllData(backupData)

            let restored = try AccountAppearanceStore(context: context).appearance(for: bareID)
            #expect(restored?.isFavorite == true)
            #expect(restored?.tintHex == "#21A038")
            #expect(restored?.presetRaw == "gradient.emerald")
            #expect(restored?.iconName == "monogram:ОС")
        }
    }

    @Test("Старый бэкап без AccountAppearance восстанавливается без краша")
    func oldBackupWithoutAppearanceRestores() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext
            let account = Account(name: "Без оформления", kind: .cash)
            context.insert(account)
            try context.save()

            let backupData = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            try repository.importAllData(backupData)

            #expect(try context.fetch(FetchDescriptor<Account>()).count == 1)
            #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).isEmpty)
        }
    }

    @Test("Импортёр идемпотентен: повторный импорт того же словаря не плодит строк")
    func importerIsIdempotent() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let dict: [String: Any] = [
            "type": "AccountAppearance",
            "id": UUID().uuidString,
            "accountID": UUID().uuidString,
            "isFavorite": true,
            "tintHex": "#123456",
            "updatedAt": Date().timeIntervalSince1970,
        ]
        try AccountAppearanceImporter.import(from: dict, context: context)
        try AccountAppearanceImporter.import(from: dict, context: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<AccountAppearance>()).count == 1)
    }

    @Test("Битая строка бэкапа отвергается, а не пишется мусором")
    func importerRejectsCorruptedRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        #expect(throws: AppError.backupCorrupted) {
            try AccountAppearanceImporter.import(
                from: ["type": "AccountAppearance", "id": "не-uuid", "accountID": "тоже-не-uuid"],
                context: context
            )
        }
    }

    @Test("DataIntegrityCleaner удаляет оформление удалённых счетов и сохраняет живое")
    func cleanerPurgesOrphans() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Живой", kind: .cash)
        let card = Card(name: "Живая карта", cardNumber: "2222")
        context.insert(account)
        context.insert(card)
        let cardUUID = try #require(UUID(uuidString: card.cardUniqueID))
        let orphanID = UUID()

        let store = AccountAppearanceStore(context: context)
        try store.upsert(accountID: account.id) { $0.isFavorite = true }
        try store.upsert(accountID: cardUUID) { $0.tintHex = "#FF0000" }
        try store.upsert(accountID: orphanID) { $0.tintHex = "#00FF00" }
        try context.save()

        try DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch(modelContext: context)

        let remaining = try store.loadAll()
        #expect(remaining.count == 2)
        #expect(remaining[account.id] != nil)
        #expect(remaining[cardUUID] != nil)
        #expect(remaining[orphanID] == nil)
    }

    /// Регрессия: владельцами оформления считались только `Account` и `Card`, поэтому оформление
    /// кредита и инвестиции признавалось сиротой и стиралось на КАЖДОМ запуске приложения.
    @Test("Чистка сирот: оформление кредита и инвестиции переживает старт")
    func cleanerKeepsCreditAndInvestmentAppearance() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let credit = Credit(
            name: "Ипотека",
            amount: 1_000_000,
            interestRate: 10,
            monthlyPayment: 20_000,
            startDate: Date(),
            termMonths: 120,
            currency: "RUB"
        )
        let investment = Investment(name: "Портфель", amount: 500, currency: "USD")
        context.insert(credit)
        context.insert(investment)
        let creditUUID = try #require(UUID(uuidString: credit.creditUniqueID))
        let investmentUUID = try #require(UUID(uuidString: investment.investmentUniqueID))

        let store = AccountAppearanceStore(context: context)
        try store.upsert(accountID: creditUUID) { $0.tintHex = "#123456" }
        try store.upsert(accountID: investmentUUID) { $0.iconName = "monogram:ПФ" }
        try context.save()

        // Два «старта» подряд: стирание проявлялось не разово, а на каждом запуске.
        try DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch(modelContext: context)
        try DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch(modelContext: context)

        let remaining = try store.loadAll()
        #expect(remaining[creditUUID]?.tintHex == "#123456")
        #expect(remaining[investmentUUID]?.iconName == "monogram:ПФ")
    }

    /// Путь создания: ViewModel читает избранное из стора и отдаёт его фабрике опций пикера
    /// ровно так же, как это делает `CashflowTransactionEditorView`.
    @Test("Cashflow-пикер: core-счёт отдаёт реальный isFavorite, а не константу false")
    func cashflowPickerReflectsCoreFavorite() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let favorite = Account(name: "Избранный", kind: .debitCard, currency: "RUB")
        let plain = Account(name: "Обычный", kind: .cash, currency: "RUB")
        context.insert(favorite)
        context.insert(plain)
        try AccountAppearanceStore(context: context).upsert(accountID: favorite.id) { $0.isFavorite = true }
        try context.save()

        let viewModel = CashflowViewModel(modelContext: context)
        let options = CashflowTransactionEditorView.selectableAccounts(
            cards: [],
            investments: [],
            transactionType: .expense,
            currency: "RUB",
            newCoreAccounts: viewModel.newCoreAccountsForCashflowPicker(),
            coreFavoriteAccountIDs: viewModel.coreAccountFavoriteIDsForCashflowPicker()
        )

        let favoriteOption = try #require(options.first { $0.id == "core:\(favorite.id.uuidString)" })
        let plainOption = try #require(options.first { $0.id == "core:\(plain.id.uuidString)" })
        #expect(favoriteOption.isFavorite == true)
        #expect(plainOption.isFavorite == false)
        #expect(favoriteOption.pickerTitle == "★ Избранный")
    }
}
