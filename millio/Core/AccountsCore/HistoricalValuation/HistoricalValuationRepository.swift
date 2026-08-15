import Foundation
import SwiftData

/// One process-local critical section shared by every repository actor instance.
///
/// `@ModelActor` serializes only calls made through the same actor. DI reconstruction or tests may
/// create several actors for one store, so publication must not rely on instance isolation alone.
private final class HistoricalValuationPublicationCoordinator: @unchecked Sendable {
    static let shared = HistoricalValuationPublicationCoordinator()

    private let lock = NSLock()

    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

/// Local V7 repository for immutable closes.
///
/// Actor serialization plus a refetch after save makes concurrent publication through one
/// process-local repository idempotent. SwiftData has no uniqueness constraint here; physical
/// duplicates restored from backup are resolved by a stable `(publishedAt, id)` winner and the
/// losers are quarantined without deleting their evidence.
@ModelActor
actor HistoricalValuationRepository {
    struct InvalidRecordCleanup: Equatable, Sendable {
        let inspectedCount: Int
        let deletedCount: Int
    }

    private struct Candidate {
        let model: HistoricalPortfolioValuation
        let result: HistoricalValuationResult
    }

    func publish(
        _ result: HistoricalValuationResult,
        publishedAt: Date,
        revisionReasonCode: String? = nil,
        maximumManifestBytes: Int = HistoricalPortfolioValuation.maximumManifestBytes
    ) throws -> HistoricalValuationResult {
        try HistoricalValuationPublicationCoordinator.shared.withLock {
            let liveReadiness = HistoricalValuationReadinessCoordinator.shared.snapshot(
                scopeID: result.key.scopeID
            )
            guard liveReadiness.readiness == .ready else {
                throw HistoricalValuationRepositoryError.scopeNotReady(
                    liveReadiness.readiness.reasonCode ?? "scope_not_ready"
                )
            }
            guard liveReadiness.token == result.readinessToken else {
                throw HistoricalValuationRepositoryError.scopeNotReady(
                    "scope_changed_during_valuation"
                )
            }
            let proposed = try HistoricalPortfolioValuation.make(
                from: result,
                publishedAt: publishedAt,
                revisionReasonCode: revisionReasonCode,
                maximumManifestBytes: maximumManifestBytes
            )

            let existing = try fetchRows(logicalID: proposed.logicalID)
            if !existing.isEmpty {
                let winner = try resolveWinner(
                    in: existing,
                    maximumManifestBytes: maximumManifestBytes
                ).result
                try validateLiveReadiness(of: winner)
                return winner
            }

            let priorRevisions = try fetchRows(baseKey: result.key)
            if !priorRevisions.isEmpty {
                guard let revisionReasonCode,
                      !revisionReasonCode.trimmingCharacters(
                        in: .whitespacesAndNewlines
                      ).isEmpty else {
                    throw HistoricalValuationRepositoryError.revisionReasonRequired
                }
            }

            modelContext.insert(proposed)
            let beforeSave = HistoricalValuationReadinessCoordinator.shared.snapshot(
                scopeID: result.key.scopeID
            )
            guard beforeSave.readiness == .ready,
                  beforeSave.token == result.readinessToken else {
                modelContext.delete(proposed)
                throw HistoricalValuationRepositoryError.scopeNotReady(
                    beforeSave.readiness.reasonCode ?? "scope_changed_before_publish"
                )
            }
            do {
                try modelContext.save()
            } catch {
                // This actor owns its context exclusively. A failed insert must not remain visible
                // to a retry or be resurrected by a later repository save.
                modelContext.rollback()
                throw error
            }

            // Refetch is part of the contract: it also converges if an import inserted a duplicate
            // between repository construction and publication.
            let persisted = try fetchRows(logicalID: proposed.logicalID)
            let winner = try resolveWinner(
                in: persisted,
                maximumManifestBytes: maximumManifestBytes
            ).result
            try validateLiveReadiness(of: winner)
            return winner
        }
    }

    func valuation(
        for key: HistoricalValuationKey,
        maximumManifestBytes: Int = HistoricalPortfolioValuation.maximumManifestBytes
    ) throws -> HistoricalValuationResult? {
        let rows = try fetchRows(logicalID: HistoricalPortfolioValuation.logicalID(for: key))
        guard !rows.isEmpty else { return nil }
        let result = try resolveWinner(in: rows, maximumManifestBytes: maximumManifestBytes).result
        try validateLiveReadiness(of: result)
        return result
    }

    func publishedValuations(
        scopeID: String,
        maximumManifestBytes: Int = HistoricalPortfolioValuation.maximumManifestBytes
    ) throws -> [HistoricalValuationResult] {
        let requestedScopeID = scopeID
        let descriptor = FetchDescriptor<HistoricalPortfolioValuation>(
            predicate: #Predicate { $0.scopeID == requestedScopeID }
        )
        let rows = try modelContext.fetch(descriptor)
        let grouped = Dictionary(grouping: rows, by: \.logicalID)
        let results = try grouped.keys.sorted().map { logicalID in
            try resolveWinner(
                in: grouped[logicalID] ?? [],
                maximumManifestBytes: maximumManifestBytes
            ).result
        }
        try results.forEach(validateLiveReadiness)
        return results
    }

    func physicalRecordCount(for key: HistoricalValuationKey) throws -> Int {
        try fetchRows(logicalID: HistoricalPortfolioValuation.logicalID(for: key)).count
    }

    func quarantinedRecordCount(for key: HistoricalValuationKey) throws -> Int {
        try fetchRows(logicalID: HistoricalPortfolioValuation.logicalID(for: key))
            .filter(\.isQuarantined)
            .count
    }

    /// Removes only derived close rows that fail the same canonical decoder used by readers.
    /// Source accounts/events and valid closes are outside this repair boundary. The shared
    /// publication lock prevents a concurrent publisher from racing the scan-and-save transaction.
    func deleteInvalidRecords(
        scopeID: String,
        maximumManifestBytes: Int = HistoricalPortfolioValuation.maximumManifestBytes
    ) throws -> InvalidRecordCleanup {
        try HistoricalValuationPublicationCoordinator.shared.withLock {
            let requestedScopeID = scopeID
            let rows = try modelContext.fetch(FetchDescriptor<HistoricalPortfolioValuation>(
                predicate: #Predicate { $0.scopeID == requestedScopeID }
            ))
            let invalidRows = rows.filter { row in
                do {
                    _ = try row.decodedResult(maximumManifestBytes: maximumManifestBytes)
                    return false
                } catch {
                    return true
                }
            }
            guard !invalidRows.isEmpty else {
                return InvalidRecordCleanup(inspectedCount: rows.count, deletedCount: 0)
            }
            invalidRows.forEach(modelContext.delete)
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw error
            }
            return InvalidRecordCleanup(
                inspectedCount: rows.count,
                deletedCount: invalidRows.count
            )
        }
    }

    private func fetchRows(logicalID: String) throws -> [HistoricalPortfolioValuation] {
        let requestedLogicalID = logicalID
        return try modelContext.fetch(FetchDescriptor(
            predicate: #Predicate<HistoricalPortfolioValuation> {
                $0.logicalID == requestedLogicalID
            }
        ))
    }

    /// A persisted close is immutable evidence, not permission to bypass current scope state.
    /// Restore/reconciliation/backfill may begin after the row was published, so every read must
    /// validate both readiness and the generation token immediately before returning the value.
    private func validateLiveReadiness(of result: HistoricalValuationResult) throws {
        let live = HistoricalValuationReadinessCoordinator.shared.snapshot(scopeID: result.key.scopeID)
        guard live.readiness == .ready else {
            throw HistoricalValuationRepositoryError.scopeNotReady(
                live.readiness.reasonCode ?? "scope_not_ready"
            )
        }
        guard live.token == result.readinessToken else {
            throw HistoricalValuationRepositoryError.scopeNotReady("scope_changed_since_publish")
        }
    }

    private func fetchRows(
        baseKey key: HistoricalValuationKey
    ) throws -> [HistoricalPortfolioValuation] {
        let schemaVersion = key.schemaVersion
        let scopeID = key.scopeID
        let dayKey = key.dayKey
        let timeZoneID = key.timeZoneID
        let displayCurrency = key.displayCurrency
        let policyVersion = key.valuationPolicyVersion
        return try modelContext.fetch(FetchDescriptor(
            predicate: #Predicate<HistoricalPortfolioValuation> {
                $0.schemaVersion == schemaVersion
                    && $0.scopeID == scopeID
                    && $0.dayKey == dayKey
                    && $0.timeZoneID == timeZoneID
                    && $0.displayCurrency == displayCurrency
                    && $0.valuationPolicyVersion == policyVersion
            }
        ))
    }

    private func resolveWinner(
        in rows: [HistoricalPortfolioValuation],
        maximumManifestBytes: Int
    ) throws -> Candidate {
        var valid: [Candidate] = []
        var firstFailure: Error?
        var changedQuarantine = false

        for row in rows {
            do {
                valid.append(.init(
                    model: row,
                    result: try row.decodedResult(maximumManifestBytes: maximumManifestBytes)
                ))
            } catch {
                if firstFailure == nil { firstFailure = error }
                row.isQuarantined = true
                row.quarantineReasonCode = "corrupted_record"
                changedQuarantine = true
            }
        }

        guard !valid.isEmpty else {
            if changedQuarantine { try modelContext.save() }
            throw firstFailure ?? HistoricalValuationRepositoryError.recordCorrupted
        }

        valid.sort { lhs, rhs in
            if lhs.model.publishedAt != rhs.model.publishedAt {
                return lhs.model.publishedAt < rhs.model.publishedAt
            }
            return lhs.model.id.uuidString < rhs.model.id.uuidString
        }
        let winner = valid[0]
        if winner.model.isQuarantined || winner.model.quarantineReasonCode != nil {
            winner.model.isQuarantined = false
            winner.model.quarantineReasonCode = nil
            changedQuarantine = true
        }
        for loser in valid.dropFirst() {
            loser.model.isQuarantined = true
            loser.model.quarantineReasonCode = "duplicate_logical_key"
            changedQuarantine = true
        }
        if changedQuarantine { try modelContext.save() }
        return winner
    }
}
