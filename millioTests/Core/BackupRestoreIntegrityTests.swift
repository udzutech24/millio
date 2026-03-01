import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct BackupRestoreIntegrityTests {
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
            HistoricalRate.self
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
    func testCashflowViewModelReloadsAfterRestoreCompletedEvent() throws {
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
        #expect(groups.first?.updatedAt == newerGroup.updatedAt)
        
        let accounts = try context.fetch(FetchDescriptor<FinanceAccount>())
        #expect(accounts.count == 1)
        #expect(accounts.first?.group?.groupUniqueID == groups.first?.groupUniqueID)
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
