import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct BackupRestoreIntegrityTests {
    private func makeContainer() -> ModelContainer {
        // [Ф5c.7 contract] Account/AccountGroup/AccountEvent/AccountDailySnapshot добавлены — без них
        // core-фикстуры молча не сохраняются/не читаются (тип не в Schema, не ошибка insert/save).
        let schema = Schema([
            Item.self,
            Card.self,
            Credit.self,
            Investment.self,
            FinanceGroup.self,
            FinanceAccount.self,
            CashflowTransaction.self,
            CashflowCustomCategory.self,
            HistoricalRate.self,
            Account.self,
            AccountGroup.self,
            AccountEvent.self,
            AccountDailySnapshot.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
    
    private func resetAll(in context: ModelContext) throws {
        try context.deleteAll(CashflowTransaction.self)
        try context.deleteAll(CashflowCustomCategory.self)
        try context.deleteAll(HistoricalRate.self)
        try context.deleteAll(FinanceAccount.self)
        try context.deleteAll(FinanceGroup.self)
        try context.deleteAll(Investment.self)
        try context.deleteAll(Credit.self)
        try context.deleteAll(Card.self)
        try context.deleteAll(Item.self)
        try context.save()
    }
    
    @Test("Restore не создает дубли при последующих сохранениях mainContext")
    func testRestoreDoesNotCreateDuplicatesViaStaleMainContextObjects() async throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let group = FinanceGroup(name: "Карты", colorHex: "#FFFFFF", order: 0)
        context.insert(group)
        try context.save()
        
        let backupData = try DataRepository.exportAllData(from: context)
        
        let repository = DataRepository(modelContext: context, modelContainer: container)
        let staleGroupRef = group
        
        try await repository.clearAllDataAsync()
        try await repository.importAllDataAsync(backupData)
        
        staleGroupRef.isFavorite.toggle()
        do {
            try context.save()
        } catch {
        }
        
        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        #expect(groups.count == 1)
        #expect(Set(groups.map(\.groupUniqueID)).count == groups.count)
    }
    
    @Test("CashflowViewModel перезагружает историю после BackupEvent.restoreCompleted")
    func testCashflowViewModelReloadsAfterRestoreCompletedEvent() async throws {
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let viewModel = CashflowViewModel(modelContext: context)
        #expect(viewModel.state.transactions.isEmpty)
        
        let transaction = CashflowTransaction(
            transactionType: .income,
            amount: 100,
            currency: "RUB",
            transactionDate: Date()
        )
        context.insert(transaction)
        try context.save()
        
        EventBus.shared.publish(BackupEvent.restoreCompleted)
        await Task.yield()
        
        #expect(viewModel.state.transactions.count == 1)
    }
    
    @Test("DataIntegrityCleaner удаляет дубликаты Card по cardUniqueID")
    func testDataIntegrityCleanerDedupesCardsByUniqueID() throws {
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let sharedID = "E06F30A6-D3B4-4530-983C-DB47854CB99F"
        
        let older = Card(
            name: "Карта 1",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        older.uniqueID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1)
        
        let newer = Card(
            name: "Карта 1",
            cardNumber: "0000",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        newer.uniqueID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        
        context.insert(older)
        context.insert(newer)
        try context.save()
        
        try DataIntegrityCleaner.dedupeAll(modelContext: context)
        
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        #expect(cards.first?.cardUniqueID == sharedID)
    }
    
    @Test("DataIntegrityCleaner удаляет дубликаты Credit по creditUniqueID, оставляя самый новый updatedAt")
    func testDataIntegrityCleanerDedupesCreditsByUniqueIDKeepingNewest() throws {
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let sharedID = "CREDIT-SHARED-ID"
        
        let older = Credit(
            name: "Кредит",
            amount: 100_000,
            interestRate: 10,
            monthlyPayment: 10_000,
            startDate: Date(timeIntervalSince1970: 0),
            termMonths: 12,
            currency: "RUB"
        )
        older.uniqueID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1)
        
        let newer = Credit(
            name: "Кредит",
            amount: 100_000,
            interestRate: 10,
            monthlyPayment: 10_000,
            startDate: Date(timeIntervalSince1970: 0),
            termMonths: 12,
            currency: "RUB"
        )
        newer.uniqueID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        
        context.insert(older)
        context.insert(newer)
        try context.save()
        
        try DataIntegrityCleaner.dedupeAll(modelContext: context)
        
        let credits = try context.fetch(FetchDescriptor<Credit>())
        #expect(credits.count == 1)
        #expect(credits.first?.creditUniqueID == sharedID)
        #expect(credits.first?.updatedAt == newer.updatedAt)
    }
    
    @Test("DataIntegrityCleaner удаляет дубликаты Investment по investmentUniqueID, оставляя самый новый updatedAt")
    func testDataIntegrityCleanerDedupesInvestmentsByUniqueIDKeepingNewest() throws {
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let sharedID = "INVEST-SHARED-ID"
        
        let older = Investment(
            name: "Актив",
            investmentType: .positive,
            category: .stocks,
            amount: 10,
            currency: "RUB"
        )
        older.uniqueID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1)
        
        let newer = Investment(
            name: "Актив",
            investmentType: .positive,
            category: .stocks,
            amount: 10,
            currency: "RUB"
        )
        newer.uniqueID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        
        context.insert(older)
        context.insert(newer)
        try context.save()
        
        try DataIntegrityCleaner.dedupeAll(modelContext: context)
        
        let investments = try context.fetch(FetchDescriptor<Investment>())
        #expect(investments.count == 1)
        #expect(investments.first?.investmentUniqueID == sharedID)
        #expect(investments.first?.updatedAt == newer.updatedAt)
    }
    
    @Test("DataIntegrityCleaner удаляет дубликаты FinanceGroup и переносит связанные FinanceAccount")
    func testDataIntegrityCleanerDedupesFinanceGroupsAndReassignsAccounts() throws {
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let sharedCreatedAt = Date(timeIntervalSince1970: 123)
        
        let olderGroup = FinanceGroup(name: "Группа", colorHex: "#FFFFFF", order: 0)
        olderGroup.createdAt = sharedCreatedAt
        olderGroup.updatedAt = Date(timeIntervalSince1970: 1)
        
        let newerGroup = FinanceGroup(name: "Группа", colorHex: "#FFFFFF", order: 0)
        newerGroup.createdAt = sharedCreatedAt
        newerGroup.updatedAt = Date(timeIntervalSince1970: 2)
        
        let account = FinanceAccount(accountType: .card, accountID: "ACC-1")
        account.group = olderGroup
        
        context.insert(olderGroup)
        context.insert(newerGroup)
        context.insert(account)
        try context.save()
        
        try DataIntegrityCleaner.dedupeAll(modelContext: context)
        
        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        #expect(groups.count == 1)
        #expect(groups.first?.updatedAt == Date(timeIntervalSince1970: 2))
        
        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.group?.groupUniqueID == groups.first?.groupUniqueID)
        #expect(accounts.first?.group?.updatedAt == Date(timeIntervalSince1970: 2))
    }
    
    // MARK: - Round-trip

    @Test("DataRepository: Card+Group видны через fetch после export→clear→import")
    func testFullRoundTripDataLayerCardAndGroupVisibleAfterRestore() async throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()

        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF", order: 0)
        context.insert(group)
        let card = Card(
            name: "Тест",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 500
        )
        context.insert(card)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        context.insert(account)
        try context.save()

        let backupData = try DataRepository.exportAllData(from: context)
        let repository = DataRepository(modelContext: context, modelContainer: container)

        try await repository.clearAllDataAsync()
        let groupsAfterClear = try context.fetch(FetchDescriptor<FinanceGroup>())
        #expect(groupsAfterClear.isEmpty, "Store должен быть пустым после clearAllData")

        try await repository.importAllDataAsync(backupData)

        let groups = try context.fetch(FetchDescriptor<FinanceGroup>())
        let cards = try context.fetch(FetchDescriptor<Card>())
        #expect(groups.count == 1, "Должна быть 1 группа после restore")
        #expect(groups.first?.name == "Основная")
        #expect(cards.count == 1, "Должна быть 1 карта после restore")
        #expect(cards.first?.balance == 500)
    }

    @Test("FinanceViewModel: state.groups и availableCards видны после restoreCompleted")
    /// [Ф5c.7 contract] `state.groups` теперь core-primary (`[AccountGroup]`) — добавлена core-фикстура
    /// + `AccountsCoreFeatureRegistration.register()` (иначе `Account`/`AccountGroup` не участвуют в
    /// backup export/import). Легаси `availableCards` — fallback-хвост, проверяется отдельно (не изменилось).
    func testFinanceViewModelShowsDataAfterRestoreRoundTrip() async throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF", order: 0)
        context.insert(group)
        let card = Card(
            name: "Тест",
            cardNumber: "1234",
            bank: .other,
            cardType: .debit,
            currency: "RUB",
            balance: 500
        )
        context.insert(card)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        context.insert(account)

        let coreGroup = AccountGroup(name: "Core Основная")
        context.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: context)
        _ = try coreService.createAccount(name: "Core Тест", kind: .debitCard, currency: "RUB", openingBalance: 300, group: coreGroup)
        try context.save()

        let backupData = try DataRepository.exportAllData(from: context)
        let repository = DataRepository(modelContext: context, modelContainer: container)

        let viewModel = FinanceViewModel(modelContext: context, skipInitialLoad: true)

        try await repository.clearAllDataAsync()
        try await repository.importAllDataAsync(backupData)

        EventBus.shared.publish(BackupEvent.restoreCompleted)

        // FinanceViewModel обрабатывает событие через fire-and-forget Task — ждём
        var stateVisible = false
        for _ in 0..<50 {
            await Task.yield()
            if !viewModel.state.groups.isEmpty {
                stateVisible = true
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        #expect(stateVisible, "FinanceViewModel.state.groups (core) должны появиться после restoreCompleted")
        #expect(viewModel.state.groups.first?.name == "Core Основная")
        #expect(!viewModel.state.availableCards.isEmpty, "availableCards (легаси-fallback) должны появиться после restoreCompleted")
    }

    @Test("runIfNeeded выполняется только один раз и выставляет флаг в UserDefaults")
    func testDataIntegrityCleanerRunIfNeededRunsOnce() throws {
        let defaults = UserDefaults.standard
        let key = "data_integrity_cleanup_v1"
        let previousValue = defaults.object(forKey: key)
        defer {
            if let previousValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)
        
        let container = makeContainer()
        let context = container.mainContext
        try resetAll(in: context)
        
        let sharedID = "RUN-IF-NEEDED-ID"
        let older = Card(name: "Карта", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB", balance: 10)
        older.uniqueID = sharedID
        older.updatedAt = Date(timeIntervalSince1970: 1)
        
        let newer = Card(name: "Карта", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB", balance: 10)
        newer.uniqueID = sharedID
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        
        context.insert(older)
        context.insert(newer)
        try context.save()
        
        try DataIntegrityCleaner.runIfNeeded(modelContext: context)
        #expect(defaults.bool(forKey: key) == true)
        
        var cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 1)
        
        let duplicate = Card(name: "Карта", cardNumber: "0000", bank: .other, cardType: .debit, currency: "RUB", balance: 10)
        duplicate.uniqueID = sharedID
        duplicate.updatedAt = Date(timeIntervalSince1970: 3)
        context.insert(duplicate)
        try context.save()
        
        try DataIntegrityCleaner.runIfNeeded(modelContext: context)
        cards = try context.fetch(FetchDescriptor<Card>())
        #expect(cards.count == 2)
    }
}
