import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
struct CashflowMonthClosureTests {
    private static var retainedContainers: [ModelContainer] = []

    private func context() throws -> ModelContext {
        let schema = Schema([CashflowMonthClosureEvent.self, CashflowTransaction.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    @Test("Current and future months cannot close")
    func completedMonthRule() {
        let now = Date(timeIntervalSince1970: 1_786_406_400) // 2026-08-10 UTC
        let result = CashflowMonthReadinessCalculator.calculate(.init(
            month: now, now: now, unresolvedImportRows: 0, duplicateRows: 0,
            uncategorizedRows: 0, reconciliationPassed: nil, accountAndMonthMatch: true,
            pendingScheduledWrites: 0
        ))
        #expect(!result.canClose)
        #expect(result.blockers == ["month_not_completed"])
    }

    @Test("Close/reopen are append-only and policy follows latest event")
    func appendOnlyLifecycle() throws {
        let context = try context()
        let month = Date(timeIntervalSince1970: 1_783_814_400) // July 2026
        var tick = 0.0
        let service = CashflowMonthClosureService(modelContext: context, now: { tick += 1; return Date(timeIntervalSince1970: tick) })
        try service.close(month: month, readiness: .init(blockers: [], warnings: []), evidenceJSON: "{}")
        #expect(CashflowMonthMutationPolicy(modelContext: context).isClosed(month))
        #expect(throws: CashflowMonthMutationPolicyError.closedMonth) {
            try CashflowMonthMutationPolicy(modelContext: context).validate(.create, date: month)
        }
        try service.reopen(month: month)
        #expect(!CashflowMonthMutationPolicy(modelContext: context).isClosed(month))
        #expect(try context.fetch(FetchDescriptor<CashflowMonthClosureEvent>()).count == 2)
    }

    @Test("Repeated close is idempotent")
    func repeatedCloseDoesNotDuplicateEvent() throws {
        let context = try context()
        let month = Date(timeIntervalSince1970: 1_783_814_400)
        let service = CashflowMonthClosureService(modelContext: context)
        let readiness = CashflowMonthReadiness(blockers: [], warnings: [])
        try service.close(month: month, readiness: readiness)
        try service.close(month: month, readiness: readiness)
        #expect(try context.fetch(FetchDescriptor<CashflowMonthClosureEvent>()).count == 1)
    }

    @Test("Backup importer deduplicates the same closure event")
    func backupImportDeduplicates() throws {
        let context = try context()
        let payload: [String: Any] = [
            "eventID": "event-1",
            "monthStart": 1_783_814_400.0,
            "kindRaw": "close",
            "occurredAt": 1_786_406_400.0,
            "evidenceJSON": "{}"
        ]
        try CashflowMonthClosureEventImporter.import(from: payload, context: context)
        try CashflowMonthClosureEventImporter.import(from: payload, context: context)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<CashflowMonthClosureEvent>()).count == 1)
    }
}
