import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
struct UnifiedEntryPerformanceFixtureSeederTests {
    @Test("Performance fixture is deterministic, synthetic, and realistically large")
    func deterministicLargeFixture() throws {
        let schema = Schema([CashflowTransaction.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_775_000_000)

        try UnifiedEntryPerformanceFixtureSeeder.seed(into: context, now: now)
        let first = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(first.count == UnifiedEntryPerformanceFixtureSeeder.expectedTransactionCount)
        #expect(first.allSatisfy { $0.currency == "RUB" && $0.cardID == nil })
        let firstSignature = first
            .map { "\($0.transactionTypeRaw)|\($0.amount)|\($0.transactionDate.timeIntervalSince1970)" }
            .sorted()

        try UnifiedEntryPerformanceFixtureSeeder.seed(into: context, now: now)
        let second = try context.fetch(FetchDescriptor<CashflowTransaction>())
        let secondSignature = second
            .map { "\($0.transactionTypeRaw)|\($0.amount)|\($0.transactionDate.timeIntervalSince1970)" }
            .sorted()
        #expect(second.count == UnifiedEntryPerformanceFixtureSeeder.expectedTransactionCount)
        #expect(secondSignature == firstSignature)
    }
}
