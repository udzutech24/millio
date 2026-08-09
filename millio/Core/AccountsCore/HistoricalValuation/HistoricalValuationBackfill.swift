import Foundation
import SwiftData

@MainActor
enum HistoricalValuationActivationPipeline {
    /// Snapshot backfill owns a readiness generation transition. Historical closes must be
    /// evaluated only after that transition reaches a terminal state, on every activation.
    static func run(
        snapshotBackfill: () async -> Void,
        historicalMaintenance: () async -> Void
    ) async {
        await snapshotBackfill()
        await historicalMaintenance()
    }
}

@MainActor
protocol HistoricalPortfolioSeriesProducing: AnyObject {
    func series(for query: HistoricalPortfolioSeriesQuery) async -> HistoricalPortfolioSeriesResult
}

extension HistoricalPortfolioSeriesProducer: HistoricalPortfolioSeriesProducing {}

enum HistoricalValuationBackfillState: Codable, Equatable, Sendable {
    case notAttempted
    case complete
    case incomplete(reasonCode: String)
}

struct HistoricalValuationBackfillKey: Codable, Hashable, Sendable {
    let scopeID: String
    let dayKey: String
    let timeZoneID: String
    let displayCurrency: String
    let valuationPolicyVersion: Int
    /// `nil` is the portfolio close. Account keys make interruption recovery granular without
    /// requiring a new schema version for rollout-only state.
    let opaqueAccountID: String?
}

protocol HistoricalValuationBackfillCheckpointStoring: Sendable {
    func state(for key: HistoricalValuationBackfillKey) -> HistoricalValuationBackfillState
    func set(_ state: HistoricalValuationBackfillState, for key: HistoricalValuationBackfillKey)
}

/// Durable rollout checkpoint storage. Financial evidence remains in V7; these small operational
/// markers deliberately live outside the frozen schema and survive reader rollback/relaunch.
final class HistoricalValuationBackfillCheckpointStore: HistoricalValuationBackfillCheckpointStoring,
    @unchecked Sendable {
    private struct Entry: Codable {
        let key: HistoricalValuationBackfillKey
        let state: HistoricalValuationBackfillState
    }

    private static let storageKey = "historical_valuation_backfill_v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func state(for key: HistoricalValuationBackfillKey) -> HistoricalValuationBackfillState {
        lock.withLock { entries()[key] ?? .notAttempted }
    }

    func set(_ state: HistoricalValuationBackfillState, for key: HistoricalValuationBackfillKey) {
        lock.withLock {
            var values = entries()
            values[key] = state
            let encoded = values.map { Entry(key: $0.key, state: $0.value) }
                .sorted { Self.sortKey($0.key) < Self.sortKey($1.key) }
            guard let data = try? JSONEncoder().encode(encoded) else { return }
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private func entries() -> [HistoricalValuationBackfillKey: HistoricalValuationBackfillState] {
        guard let data = defaults.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return [:] }
        return Dictionary(decoded.map { ($0.key, $0.state) }, uniquingKeysWith: { _, latest in latest })
    }

    private static func sortKey(_ key: HistoricalValuationBackfillKey) -> String {
        [key.scopeID, key.dayKey, key.timeZoneID, key.displayCurrency,
         String(key.valuationPolicyVersion), key.opaqueAccountID ?? ""].joined(separator: "\u{1F}")
    }
}

actor HistoricalValuationBackfillCoordinator {
    typealias Executor = @Sendable (HistoricalValuationBackfillKey) async throws -> Bool

    private let checkpoints: any HistoricalValuationBackfillCheckpointStoring
    private let execute: Executor

    init(
        checkpoints: any HistoricalValuationBackfillCheckpointStoring,
        execute: @escaping Executor
    ) {
        self.checkpoints = checkpoints
        self.execute = execute
    }

    /// Persists after every unit. Cancellation leaves only the current unit not-attempted, while
    /// an evaluated but incomplete close is explicitly retryable on the next invocation.
    @discardableResult
    func resume(_ keys: [HistoricalValuationBackfillKey], force: Bool = false) async -> Bool {
        for key in keys.sorted(by: { Self.sortKey($0) < Self.sortKey($1) }) {
            guard !Task.isCancelled else { return false }
            guard force || checkpoints.state(for: key) != .complete else { continue }
            do {
                let complete = try await execute(key)
                checkpoints.set(
                    complete ? .complete : .incomplete(reasonCode: "valuation_incomplete"),
                    for: key
                )
            } catch is CancellationError {
                return false
            } catch {
                checkpoints.set(.incomplete(reasonCode: "evaluation_failed"), for: key)
            }
        }
        return keys.allSatisfy { checkpoints.state(for: $0) == .complete }
    }

    private static func sortKey(_ key: HistoricalValuationBackfillKey) -> String {
        [key.dayKey, key.opaqueAccountID ?? "", key.scopeID].joined(separator: "\u{1F}")
    }
}

/// Connects a durable rebuild obligation to granular backfill. The marker is acknowledged only
/// after every requested unit is durably complete. A newer concurrently-enqueued marker is kept by
/// `HistoricalValuationRebuildQueue.acknowledge`'s compare-and-remove contract.
actor HistoricalValuationRebuildBackfillRunner {
    typealias Pending = @Sendable (String) throws -> HistoricalValuationRebuildRequest?
    typealias Acknowledge = @Sendable (HistoricalValuationRebuildRequest) throws -> Bool

    private let coordinator: HistoricalValuationBackfillCoordinator
    private let pending: Pending
    private let acknowledge: Acknowledge

    init(
        coordinator: HistoricalValuationBackfillCoordinator,
        pending: @escaping Pending = { try HistoricalValuationRebuildQueue.pending(scopeID: $0) },
        acknowledge: @escaping Acknowledge = { try HistoricalValuationRebuildQueue.acknowledge($0) }
    ) {
        self.coordinator = coordinator
        self.pending = pending
        self.acknowledge = acknowledge
    }

    @discardableResult
    func resume(scopeID: String, keys: [HistoricalValuationBackfillKey]) async throws -> Bool {
        guard let request = try pending(scopeID) else { return true }
        guard !keys.isEmpty, keys.allSatisfy({ $0.scopeID == scopeID }) else { return false }
        // A rebuild request represents a new source generation. Old `.complete` checkpoints may
        // predate restore/reconciliation and therefore cannot prove this marker; force replay.
        guard await coordinator.resume(keys, force: true) else { return false }
        return try acknowledge(request)
    }
}

/// Executes a checkpoint through the same structured producer used by readers. This adapter never
/// calls the numeric compatibility API. A non-UUID account checkpoint is rejected because it cannot
/// be scoped without a verified legacy identity mapping; the portfolio checkpoint remains safe.
@MainActor
final class HistoricalValuationSeriesBackfillExecutor {
    private let producer: any HistoricalPortfolioSeriesProducing

    init(producer: any HistoricalPortfolioSeriesProducing) {
        self.producer = producer
    }

    func execute(_ key: HistoricalValuationBackfillKey) async -> Bool {
        guard let timeContext = HistoricalValuationTimeContext(ianaTimeZoneID: key.timeZoneID),
              let date = Self.endOfDay(dayKey: key.dayKey, timeContext: timeContext) else { return false }
        let accountScope: HistoricalPortfolioAccountScope
        if let opaqueID = key.opaqueAccountID {
            guard let id = UUID(uuidString: opaqueID) else { return false }
            accountScope = .accountIDs([id])
        } else {
            accountScope = .portfolio
        }
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: date, end: date),
            timeZoneID: key.timeZoneID,
            displayCurrency: key.displayCurrency,
            accountScope: accountScope,
            samplingPolicy: .exact([date]),
            valuationPolicyVersion: key.valuationPolicyVersion
        )
        guard let result = await producer.series(for: query).points.first?.valuation else { return false }
        return result.state == .complete
            && result.finality == .closed
            && result.publication == .published
    }

    private static func endOfDay(
        dayKey: String,
        timeContext: HistoricalValuationTimeContext
    ) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.gregorianBackfill(in: timeContext.timeZone)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeContext.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dayKey).map(timeContext.endOfDay(for:))
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension Calendar {
    static func gregorianBackfill(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}

/// Production composition for both a pending rebuild and ordinary missed-day lazy closes.
/// Work is derived from the local source graph, sorted by day, and checkpointed after each close.
/// Repeated activation is cheap because completed keys are skipped by the coordinator.
@MainActor
final class HistoricalValuationProductionMaintenance {
    private let modelContext: ModelContext
    private let scopeID: String
    private let clock: any HistoricalValuationClock
    private let defaults: UserDefaults
    private let coordinator: HistoricalValuationBackfillCoordinator
    private let rebuildRunner: HistoricalValuationRebuildBackfillRunner

    init(
        modelContainer: ModelContainer,
        scopeID: String,
        clock: any HistoricalValuationClock = SystemHistoricalValuationClock(),
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContainer.mainContext
        self.scopeID = scopeID
        self.clock = clock
        self.defaults = defaults

        let totals = AccountsTotalsService(
            modelContext: modelContainer.mainContext,
            rebuilder: AccountSnapshotRebuilder(modelContainer: modelContainer),
            rateService: CurrencyRateService.shared,
            marketPriceService: AccountMarketPriceService(modelContext: modelContainer.mainContext),
            scopeReadiness: {
                HistoricalValuationReadinessCoordinator.shared.readiness(scopeID: scopeID)
            }
        )
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: totals,
            scopeID: scopeID,
            clock: clock,
            closeStore: HistoricalValuationCloseStore(modelContainer: modelContainer)
        )
        let executor = HistoricalValuationSeriesBackfillExecutor(producer: producer)
        let coordinator = HistoricalValuationBackfillCoordinator(
            checkpoints: HistoricalValuationBackfillCheckpointStore(defaults: defaults),
            execute: { key in await executor.execute(key) }
        )
        self.coordinator = coordinator
        self.rebuildRunner = HistoricalValuationRebuildBackfillRunner(
            coordinator: coordinator,
            pending: { try HistoricalValuationRebuildQueue.pending(scopeID: $0, defaults: defaults) },
            acknowledge: { try HistoricalValuationRebuildQueue.acknowledge($0, defaults: defaults) }
        )
    }

    /// Runs at cold start and app activation. It closes every eligible civil day in order, then
    /// acknowledges a pending full-scope rebuild only after those same durable units are complete.
    func resumeMissedDays() async {
        guard let keys = plannedKeys() else {
            AppLogger.log(.error, category: "AccountsCore", "Historical close planning failed")
            return
        }
        guard !keys.isEmpty else { return }

        do {
            if try HistoricalValuationRebuildQueue.pending(scopeID: scopeID, defaults: defaults) != nil {
                guard try await rebuildRunner.resume(scopeID: scopeID, keys: keys) else {
                    AppLogger.log(.warning, category: "AccountsCore", "Historical rebuild incomplete")
                    return
                }
            } else if !(await coordinator.resume(keys)) {
                AppLogger.log(.warning, category: "AccountsCore", "Historical close backfill incomplete")
            }
        } catch {
            AppLogger.log(.error, category: "AccountsCore", "Historical rebuild marker failed")
        }
    }

    private func plannedKeys() -> [HistoricalValuationBackfillKey]? {
        let accounts: [Account]
        let events: [AccountEvent]
        do {
            accounts = try modelContext.fetch(FetchDescriptor<Account>())
            events = try modelContext.fetch(FetchDescriptor<AccountEvent>())
        } catch { return nil }

        let timeZoneID = TimeZone.current.identifier
        guard let timeContext = HistoricalValuationTimeContext(ianaTimeZoneID: timeZoneID) else {
            return nil
        }
        let today = timeContext.startOfDay(for: clock.now)
        guard let lastClosedDay = Calendar.gregorianBackfill(in: timeContext.timeZone)
            .date(byAdding: .day, value: -1, to: today) else { return [] }
        let candidates = accounts.map(\.createdAt) + events.map(\.date)
        let first = timeContext.startOfDay(for: min(candidates.min() ?? lastClosedDay, lastClosedDay))
        let currency = HistoricalValuationCurrencyCode.normalized(
            SettingsManager.shared.primaryCurrencyCode
        )
        guard HistoricalValuationCurrencyCode.isSupported(currency) else { return nil }

        var keys: [HistoricalValuationBackfillKey] = []
        var cursor = first
        while cursor <= lastClosedDay {
            keys.append(.init(
                scopeID: scopeID,
                dayKey: timeContext.dayKey(for: cursor),
                timeZoneID: timeZoneID,
                displayCurrency: currency,
                valuationPolicyVersion: 1,
                opaqueAccountID: nil
            ))
            guard let next = Calendar.gregorianBackfill(in: timeContext.timeZone)
                .date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return keys
    }
}
