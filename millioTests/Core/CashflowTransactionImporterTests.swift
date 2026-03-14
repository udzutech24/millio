import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct CashflowTransactionImporterTests {
    private static let container: ModelContainer = {
        let schema = Schema([CashflowTransaction.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }
    
    @Test("CashflowTransactionImporter does not crash when transactionUniqueID exists")
    func testImporterDoesNotQueryComputedUniqueID() throws {
        let now = Date()
        let dict: [String: Any] = [
            "_type": "CashflowTransaction",
            "transactionTypeRaw": "expense",
            "amount": 123.45,
            "currency": "RUB",
            "transactionDate": now.timeIntervalSince1970,
            "createdAt": now.timeIntervalSince1970,
            "updatedAt": now.timeIntervalSince1970,
            "transactionUniqueID": "expense|\(now.timeIntervalSince1970)|123.45|\(now.timeIntervalSince1970)",
            "recurrenceRuleRaw": "weekly",
            "recurrenceWeekdaysRaw": "2,4",
            "recurrenceSeriesID": "series-001",
            "affectsCardBalance": false
        ]
        
        let context = makeContext()
        try context.deleteAll(CashflowTransaction.self)
        try context.save()

        try CashflowTransactionImporter.import(from: dict, context: context)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.amount == 123.45)
        #expect(fetched.first?.recurrenceRule == .weekly)
        #expect(fetched.first?.recurrenceWeekdays == [.monday, .wednesday])
        #expect(fetched.first?.recurrenceSeriesID == "series-001")
        #expect(fetched.first?.affectsCardBalance == false)
    }
}
