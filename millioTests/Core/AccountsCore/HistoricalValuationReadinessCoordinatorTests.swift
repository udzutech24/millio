import Foundation
import Testing
@testable import millio

@Suite("Historical valuation readiness", .serialized)
struct HistoricalValuationReadinessCoordinatorTests {
    @Test("Restore, reconciliation and failure never look ready")
    func lifecycleStates() {
        let coordinator = HistoricalValuationReadinessCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        #expect(coordinator.readiness(scopeID: "scope-a") == .ready)
        coordinator.beginGlobal(.restore)
        #expect(coordinator.readiness(scopeID: "scope-a") == .restoring)
        coordinator.completeGlobal(.restore)

        coordinator.begin(scopeID: "scope-a", operation: .reconciliation)
        #expect(coordinator.readiness(scopeID: "scope-a") == .reconciling)
        #expect(coordinator.readiness(scopeID: "scope-b") == .ready)
        coordinator.fail(
            scopeID: "scope-a",
            operation: .reconciliation,
            reasonCode: "reconciliation_failed"
        )
        #expect(coordinator.readiness(scopeID: "scope-a") == .failed(
            reasonCode: "reconciliation_failed"
        ))

        coordinator.begin(scopeID: "scope-a", operation: .reconciliation)
        coordinator.complete(scopeID: "scope-a", operation: .reconciliation)
        #expect(coordinator.readiness(scopeID: "scope-a") == .ready)

        coordinator.begin(scopeID: "scope-a", operation: .revisionMigration)
        #expect(coordinator.readiness(scopeID: "scope-a") == .revisionMigrating)
        coordinator.complete(scopeID: "scope-a", operation: .revisionMigration)
        #expect(coordinator.readiness(scopeID: "scope-a") == .ready)
    }

    @Test("Overlapping operations and failures do not clobber each other")
    func overlappingOperations() {
        let coordinator = HistoricalValuationReadinessCoordinator.shared
        coordinator.resetForTesting()
        defer { coordinator.resetForTesting() }

        coordinator.fail(
            scopeID: "scope-a",
            operation: .backfill,
            reasonCode: "backfill_partial_failure"
        )
        coordinator.begin(scopeID: "scope-a", operation: .revisionMigration)
        coordinator.complete(scopeID: "scope-a", operation: .revisionMigration)
        #expect(coordinator.readiness(scopeID: "scope-a") == .failed(
            reasonCode: "backfill_partial_failure"
        ))

        coordinator.begin(scopeID: "scope-a", operation: .backfill)
        coordinator.begin(scopeID: "scope-a", operation: .backfill)
        coordinator.complete(scopeID: "scope-a", operation: .backfill)
        #expect(coordinator.readiness(scopeID: "scope-a") == .backfilling)
        coordinator.complete(scopeID: "scope-a", operation: .backfill)
        #expect(coordinator.readiness(scopeID: "scope-a") == .ready)

        coordinator.begin(scopeID: "scope-a", operation: .restore)
        coordinator.begin(scopeID: "scope-a", operation: .restore)
        coordinator.complete(scopeID: "scope-a", operation: .restore)
        #expect(coordinator.readiness(scopeID: "scope-a") == .restoring)
        coordinator.fail(
            scopeID: "scope-a",
            operation: .restore,
            reasonCode: "restore_failed"
        )
        coordinator.complete(scopeID: "scope-a", operation: .restore)
        #expect(coordinator.readiness(scopeID: "scope-a") == .failed(
            reasonCode: "restore_failed"
        ))
    }

    @Test("A crash during restore is durable across coordinator recreation")
    func interruptedRestoreIsDurable() throws {
        let suiteName = "HistoricalValuationReadiness.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let beforeCrash = HistoricalValuationReadinessCoordinator(defaults: defaults)
        beforeCrash.begin(scopeID: "scope-a", operation: .restore)

        let afterRelaunch = HistoricalValuationReadinessCoordinator(defaults: defaults)
        #expect(afterRelaunch.readiness(scopeID: "scope-a") == .failed(
            reasonCode: "restore_interrupted"
        ))
    }
}
