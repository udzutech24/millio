import Foundation

enum HistoricalValuationReadinessOperation: String, Hashable, Sendable {
    case restore
    case reconciliation
    case backfill
    case revisionMigration
}

struct HistoricalValuationReadinessToken: Codable, Equatable, Sendable {
    let globalGeneration: UInt64
    let scopeGeneration: UInt64
}

struct HistoricalValuationReadinessSnapshot: Equatable, Sendable {
    let readiness: HistoricalScopeReadiness
    let token: HistoricalValuationReadinessToken
}

/// Local authority for whether persisted domain data is safe to close.
///
/// A global restore blocks every scope because the backup transport is intentionally scope-agnostic.
/// Scope-local reconciliation/backfill/migration states block only their destination store. A
/// failure stays explicit until the corresponding operation is retried successfully; it never
/// degrades to an apparently ready empty portfolio.
final class HistoricalValuationReadinessCoordinator: @unchecked Sendable {
    static let shared = HistoricalValuationReadinessCoordinator()

    private struct State {
        var activeCounts: [HistoricalValuationReadinessOperation: Int] = [:]
        var failures: [HistoricalValuationReadinessOperation: String] = [:]
        var generation: UInt64 = 0
    }

    private let lock = NSLock()
    private let defaults: UserDefaults
    private var global = State()
    private var scopes: [String: State] = [:]
    private var durableKeysWritten: Set<String> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func readiness(scopeID: String) -> HistoricalScopeReadiness {
        snapshot(scopeID: scopeID).readiness
    }

    func snapshot(scopeID: String) -> HistoricalValuationReadinessSnapshot {
        lock.lock()
        defer { lock.unlock() }
        let scope = scopes[scopeID] ?? State()
        var durableScope = scope
        for operation in Self.operationPriority {
            if let reason = defaults.string(
                forKey: Self.failureKey(scopeID: scopeID, operation: operation)
            ) {
                durableScope.failures[operation] = reason
            }
        }
        let readiness = Self.readiness(for: global)
            ?? Self.readiness(for: durableScope)
            ?? .ready
        return .init(
            readiness: readiness,
            token: .init(
                globalGeneration: global.generation,
                scopeGeneration: scope.generation
            )
        )
    }

    func beginGlobal(_ operation: HistoricalValuationReadinessOperation) {
        lock.lock()
        global.failures.removeValue(forKey: operation)
        global.activeCounts[operation, default: 0] += 1
        global.generation &+= 1
        lock.unlock()
    }

    func completeGlobal(_ operation: HistoricalValuationReadinessOperation) {
        lock.lock()
        Self.decrement(operation, in: &global)
        global.generation &+= 1
        lock.unlock()
    }

    func failGlobal(
        _ operation: HistoricalValuationReadinessOperation,
        reasonCode: String
    ) {
        lock.lock()
        Self.decrement(operation, in: &global)
        global.failures[operation] = reasonCode
        global.generation &+= 1
        lock.unlock()
    }

    func begin(scopeID: String, operation: HistoricalValuationReadinessOperation) {
        lock.lock()
        var state = scopes[scopeID] ?? State()
        state.failures.removeValue(forKey: operation)
        state.activeCounts[operation, default: 0] += 1
        state.generation &+= 1
        scopes[scopeID] = state
        let key = Self.failureKey(scopeID: scopeID, operation: operation)
        defaults.set(Self.inProgressReason(operation), forKey: key)
        durableKeysWritten.insert(key)
        lock.unlock()
    }

    func complete(scopeID: String, operation: HistoricalValuationReadinessOperation) {
        lock.lock()
        var state = scopes[scopeID] ?? State()
        Self.decrement(operation, in: &state)
        state.generation &+= 1
        scopes[scopeID] = state
        let key = Self.failureKey(scopeID: scopeID, operation: operation)
        if (state.activeCounts[operation] ?? 0) == 0,
           state.failures[operation] == nil {
            defaults.removeObject(forKey: key)
        }
        durableKeysWritten.insert(key)
        lock.unlock()
    }

    func fail(
        scopeID: String,
        operation: HistoricalValuationReadinessOperation,
        reasonCode: String
    ) {
        lock.lock()
        var state = scopes[scopeID] ?? State()
        Self.decrement(operation, in: &state)
        state.failures[operation] = reasonCode
        state.generation &+= 1
        scopes[scopeID] = state
        let key = Self.failureKey(scopeID: scopeID, operation: operation)
        defaults.set(reasonCode, forKey: key)
        durableKeysWritten.insert(key)
        lock.unlock()
    }

    #if DEBUG
    func resetForTesting() {
        lock.lock()
        global = State()
        scopes = [:]
        for key in durableKeysWritten { defaults.removeObject(forKey: key) }
        durableKeysWritten = []
        lock.unlock()
    }
    #endif

    private static func readiness(for state: State) -> HistoricalScopeReadiness? {
        if (state.activeCounts[.restore] ?? 0) > 0 { return .restoring }
        if (state.activeCounts[.reconciliation] ?? 0) > 0 { return .reconciling }
        if (state.activeCounts[.backfill] ?? 0) > 0 { return .backfilling }
        if (state.activeCounts[.revisionMigration] ?? 0) > 0 { return .revisionMigrating }
        for operation in operationPriority {
            if let reason = state.failures[operation] { return .failed(reasonCode: reason) }
        }
        return nil
    }

    private static let operationPriority: [HistoricalValuationReadinessOperation] = [
        .restore, .reconciliation, .backfill, .revisionMigration
    ]

    private static func decrement(
        _ operation: HistoricalValuationReadinessOperation,
        in state: inout State
    ) {
        let next = max(0, (state.activeCounts[operation] ?? 0) - 1)
        if next == 0 {
            state.activeCounts.removeValue(forKey: operation)
        } else {
            state.activeCounts[operation] = next
        }
    }

    private static func failureKey(
        scopeID: String,
        operation: HistoricalValuationReadinessOperation
    ) -> String {
        let scope = Data(scopeID.utf8).base64EncodedString()
        return "historicalValuation.readiness.v1.\(scope).\(operation.rawValue)"
    }

    private static func inProgressReason(
        _ operation: HistoricalValuationReadinessOperation
    ) -> String {
        switch operation {
        case .restore: "restore_interrupted"
        case .reconciliation: "reconciliation_interrupted"
        case .backfill: "backfill_interrupted"
        case .revisionMigration: "revision_migration_interrupted"
        }
    }
}
