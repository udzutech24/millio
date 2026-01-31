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
            HistoricalRate.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
    
    private func resetAll(in context: ModelContext) throws {
        try context.deleteAll(CashflowTransaction.self)
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
}
