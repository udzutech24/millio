import Foundation

struct HistoricalValuationRebuildRequest: Codable, Equatable, Sendable {
    let id: UUID
    let scopeID: String
    let reasonCode: String
    let enqueuedAt: Date
}

enum HistoricalValuationRebuildQueueError: Error, Equatable {
    case corruptedMarker
}

/// Durable handoff from restore/reconciliation to the Phase 4 lazy close producer.
///
/// Guest close rows are never copied because their scope identity is wrong for the user store.
/// Instead reconciliation enqueues one full-scope rebuild marker. Phase 4 can consume it only after
/// the destination source graph is ready; repeated merges replace the marker idempotently.
enum HistoricalValuationRebuildQueue {
    private static let keyPrefix = "historicalValuation.rebuild.v1."

    @discardableResult
    static func enqueue(
        scopeID: String,
        reasonCode: String,
        enqueuedAt: Date = Date(),
        defaults: UserDefaults = .standard
    ) throws -> HistoricalValuationRebuildRequest {
        let request = HistoricalValuationRebuildRequest(
            id: UUID(),
            scopeID: scopeID,
            reasonCode: reasonCode,
            enqueuedAt: enqueuedAt
        )
        let data = try JSONEncoder().encode(request)
        defaults.set(data, forKey: key(for: scopeID))
        return request
    }

    static func pending(
        scopeID: String,
        defaults: UserDefaults = .standard
    ) throws -> HistoricalValuationRebuildRequest? {
        guard let data = defaults.data(forKey: key(for: scopeID)) else { return nil }
        do {
            return try JSONDecoder().decode(HistoricalValuationRebuildRequest.self, from: data)
        } catch {
            throw HistoricalValuationRebuildQueueError.corruptedMarker
        }
    }

    /// Removes only the exact request that Phase 4 has rebuilt successfully. If a newer enqueue
    /// replaced it while work was running, the newer marker remains pending.
    static func acknowledge(
        _ completed: HistoricalValuationRebuildRequest,
        defaults: UserDefaults = .standard
    ) throws -> Bool {
        guard try pending(scopeID: completed.scopeID, defaults: defaults)?.id == completed.id else {
            return false
        }
        defaults.removeObject(forKey: key(for: completed.scopeID))
        return true
    }

    private static func key(for scopeID: String) -> String {
        keyPrefix + Data(scopeID.utf8).base64EncodedString()
    }
}
