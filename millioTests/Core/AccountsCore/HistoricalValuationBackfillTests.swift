import Foundation
import Testing
@testable import millio

@Suite("Historical valuation backfill")
struct HistoricalValuationBackfillTests {
    @MainActor
    @Test("snapshot readiness reaches terminal state before historical close on every activation")
    func activationOrderingIsStable() async {
        var order: [String] = []

        for activation in 1...2 {
            await HistoricalValuationActivationPipeline.run(
                snapshotBackfill: { order.append("snapshot-\(activation)") },
                historicalMaintenance: { order.append("historical-\(activation)") }
            )
        }

        #expect(order == ["snapshot-1", "historical-1", "snapshot-2", "historical-2"])
    }

    @Test("checkpoint survives store reconstruction and is isolated by scope/day/account")
    func durableGranularCheckpoint() {
        let defaults = isolatedDefaults()
        let key = makeKey(scope: "guest", day: "2026-08-07", account: "account-a")
        HistoricalValuationBackfillCheckpointStore(defaults: defaults).set(.complete, for: key)

        let relaunched = HistoricalValuationBackfillCheckpointStore(defaults: defaults)
        #expect(relaunched.state(for: key) == .complete)
        #expect(relaunched.state(for: makeKey(scope: "user", day: "2026-08-07", account: "account-a")) == .notAttempted)
        #expect(relaunched.state(for: makeKey(scope: "guest", day: "2026-08-08", account: "account-a")) == .notAttempted)
        #expect(relaunched.state(for: makeKey(scope: "guest", day: "2026-08-07", account: "account-b")) == .notAttempted)
        #expect(relaunched.state(for: makeKey(scope: "guest", day: "2026-08-07", account: "account-a",
                                                   timeZoneID: "America/Los_Angeles")) == .notAttempted)
    }

    @Test("resume skips complete work and retries incomplete work")
    func resumeIsIdempotent() async {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let complete = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        let incomplete = makeKey(scope: "guest", day: "2026-08-08", account: nil)
        store.set(.complete, for: complete)
        store.set(.incomplete(reasonCode: "offline"), for: incomplete)
        let calls = CallRecorder()
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { key in
            await calls.append(key)
            return true
        }

        await coordinator.resume([incomplete, complete])

        #expect(await calls.values == [incomplete])
        #expect(store.state(for: incomplete) == .complete)
    }

    @Test("failure is persisted as incomplete instead of falsely complete")
    func failureIsExplicit() async {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let key = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { _ in
            throw TestFailure.expected
        }

        await coordinator.resume([key])

        #expect(store.state(for: key) == .incomplete(reasonCode: "evaluation_failed"))
    }

    @Test("interrupted item remains not-attempted and completes on retry")
    func interruptionResumesCurrentItem() async {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let key = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        let attempts = AttemptCounter()
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { _ in
            if await attempts.next() == 1 { throw CancellationError() }
            return true
        }

        await coordinator.resume([key])
        #expect(store.state(for: key) == .notAttempted)
        await coordinator.resume([key])
        #expect(store.state(for: key) == .complete)
    }

    @Test("rebuild marker is acknowledged only after every backfill unit succeeds")
    func markerAckRequiresFullSuccess() async throws {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let first = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        let second = makeKey(scope: "guest", day: "2026-08-08", account: nil)
        let attempts = AttemptCounter()
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { key in
            if key == first { return true }
            return await attempts.next() > 1
        }
        let marker = HistoricalValuationRebuildRequest(
            id: UUID(), scopeID: "guest", reasonCode: "restore", enqueuedAt: Date()
        )
        let acknowledgements = AcknowledgementRecorder()
        let runner = HistoricalValuationRebuildBackfillRunner(
            coordinator: coordinator,
            pending: { _ in marker },
            acknowledge: { request in acknowledgements.append(request); return true }
        )

        #expect(try await runner.resume(scopeID: "guest", keys: [first, second]) == false)
        #expect(acknowledgements.values.isEmpty)
        #expect(try await runner.resume(scopeID: "guest", keys: [first, second]) == true)
        #expect(acknowledgements.values.map(\.id) == [marker.id])
    }

    @Test("rebuild marker replays checkpoints completed before its source generation")
    func rebuildDoesNotTrustStaleCheckpoint() async throws {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let key = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        store.set(.complete, for: key)
        let calls = CallRecorder()
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { value in
            await calls.append(value)
            return true
        }
        let marker = HistoricalValuationRebuildRequest(
            id: UUID(), scopeID: "guest", reasonCode: "restore", enqueuedAt: Date()
        )
        let runner = HistoricalValuationRebuildBackfillRunner(
            coordinator: coordinator,
            pending: { _ in marker },
            acknowledge: { _ in true }
        )

        #expect(try await runner.resume(scopeID: "guest", keys: [key]))
        #expect(await calls.values == [key])
    }

    @Test("empty or cross-scope work cannot clear a rebuild marker")
    func markerAckRejectsUnprovenCoverage() async throws {
        let store = HistoricalValuationBackfillCheckpointStore(defaults: isolatedDefaults())
        let coordinator = HistoricalValuationBackfillCoordinator(checkpoints: store) { _ in true }
        let marker = HistoricalValuationRebuildRequest(
            id: UUID(), scopeID: "guest", reasonCode: "restore", enqueuedAt: Date()
        )
        let acknowledgements = AcknowledgementRecorder()
        let runner = HistoricalValuationRebuildBackfillRunner(
            coordinator: coordinator,
            pending: { _ in marker },
            acknowledge: { request in acknowledgements.append(request); return true }
        )

        #expect(try await runner.resume(scopeID: "guest", keys: []) == false)
        #expect(try await runner.resume(
            scopeID: "guest", keys: [makeKey(scope: "user", day: "2026-08-07", account: nil)]
        ) == false)
        #expect(acknowledgements.values.isEmpty)
    }

    @MainActor
    @Test("backfill executor accepts only a closed published complete producer result")
    func executorRequiresPublishableStructuredResult() async {
        let key = makeKey(scope: "guest", day: "2026-08-07", account: nil)
        let complete = StubSeriesProducer(result: makeSeriesResult(complete: true))
        let incomplete = StubSeriesProducer(result: makeSeriesResult(complete: false))

        #expect(await HistoricalValuationSeriesBackfillExecutor(producer: complete).execute(key))
        #expect(!(await HistoricalValuationSeriesBackfillExecutor(producer: incomplete).execute(key)))
        #expect(complete.queries.first?.timeZoneID == key.timeZoneID)
        #expect(complete.queries.first?.displayCurrency == key.displayCurrency)
    }

    @MainActor
    @Test("backfill refuses an unverified opaque legacy account scope")
    func executorRejectsUnverifiedLegacyScope() async {
        let producer = StubSeriesProducer(result: makeSeriesResult(complete: true))
        let key = makeKey(scope: "guest", day: "2026-08-07", account: "legacy-card")

        #expect(!(await HistoricalValuationSeriesBackfillExecutor(producer: producer).execute(key)))
        #expect(producer.queries.isEmpty)
    }

    @MainActor
    private func makeSeriesResult(complete: Bool) -> HistoricalPortfolioSeriesResult {
        let date = Date(timeIntervalSince1970: 1_754_518_399)
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: date, end: date), timeZoneID: "Europe/Istanbul",
            displayCurrency: "USD", samplingPolicy: .exact([date])
        )
        let result = HistoricalValuationResult(
            key: .init(schemaVersion: 7, scopeID: "guest", dayKey: "2026-08-07",
                       timeZoneID: "Europe/Istanbul", displayCurrency: "USD",
                       valuationPolicyVersion: 1,
                       inputRevision: .init(accountSet: 1, financial: 1, events: 1, evidence: 1)),
            diagnosticPartialTotal: 10, finality: .closed,
            quality: complete ? .exact : .unavailable,
            expectedContributionCount: 1, resolvedContributionCount: complete ? 1 : 0,
            unresolved: complete ? [] : [
                .init(opaqueAccountID: "missing", dimension: .fxRate, reasonCode: "offline")
            ], resolutions: [], generatedAt: date
        )
        return .init(query: query, points: [
            .init(id: .init(result.key), date: date, valuation: result, accountContributions: [])
        ], generatedAt: date)
    }

    private func makeKey(
        scope: String,
        day: String,
        account: String?,
        timeZoneID: String = "Europe/Istanbul"
    ) -> HistoricalValuationBackfillKey {
        .init(scopeID: scope, dayKey: day, timeZoneID: timeZoneID,
              displayCurrency: "USD", valuationPolicyVersion: 1, opaqueAccountID: account)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "HistoricalValuationBackfillTests.\(UUID().uuidString)")!
    }
}

private actor CallRecorder {
    private(set) var values: [HistoricalValuationBackfillKey] = []
    func append(_ value: HistoricalValuationBackfillKey) { values.append(value) }
}

private actor AttemptCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private enum TestFailure: Error { case expected }

@MainActor
private final class StubSeriesProducer: HistoricalPortfolioSeriesProducing {
    let result: HistoricalPortfolioSeriesResult
    private(set) var queries: [HistoricalPortfolioSeriesQuery] = []
    init(result: HistoricalPortfolioSeriesResult) { self.result = result }
    func series(for query: HistoricalPortfolioSeriesQuery) async -> HistoricalPortfolioSeriesResult {
        queries.append(query)
        return result
    }
}

private final class AcknowledgementRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [HistoricalValuationRebuildRequest] = []
    var values: [HistoricalValuationRebuildRequest] { lock.withLock { storage } }
    func append(_ value: HistoricalValuationRebuildRequest) { lock.withLock { storage.append(value) } }
}
