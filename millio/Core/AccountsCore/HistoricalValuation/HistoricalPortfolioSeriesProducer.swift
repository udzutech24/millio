import Foundation
import SwiftData

@MainActor
protocol HistoricalValuationClosing: AnyObject {
    func closeIfNeeded(_ result: HistoricalValuationResult, publishedAt: Date) async -> HistoricalValuationResult
}

@MainActor
final class HistoricalValuationCloseStore: HistoricalValuationClosing {
    private let repository: HistoricalValuationRepository

    init(modelContainer: ModelContainer) {
        repository = HistoricalValuationRepository(modelContainer: modelContainer)
    }

    func closeIfNeeded(
        _ result: HistoricalValuationResult,
        publishedAt: Date
    ) async -> HistoricalValuationResult {
        // An incomplete result is diagnostic evidence, not a publishable close. Sending it to the
        // repository only replaces its real missing dependency with `close_repository_failed`.
        guard result.finality == .closed, result.total != nil else { return result }
        do {
            if let persisted = try await repository.valuation(for: result.key) { return persisted }
            let publishable = HistoricalValuationResult(
                key: result.key,
                diagnosticPartialTotal: result.diagnosticPartialTotal,
                finality: .closed,
                quality: result.quality,
                publication: .published,
                scopeReadiness: result.scopeReadiness,
                readinessToken: result.readinessToken,
                expectedContributionCount: result.expectedContributionCount,
                resolvedContributionCount: result.resolvedContributionCount,
                unresolved: result.unresolved,
                resolutions: result.resolutions,
                generatedAt: result.generatedAt
            )
            do {
                return try await repository.publish(publishable, publishedAt: publishedAt)
            } catch HistoricalValuationRepositoryError.revisionReasonRequired {
                return try await repository.publish(
                    publishable,
                    publishedAt: publishedAt,
                    revisionReasonCode: "historical_evidence_backfill"
                )
            }
        } catch {
            AppLogger.log(
                .error,
                category: "AccountsCore",
                "Historical close repository failed for day=\(result.key.dayKey) scope=\(result.key.scopeID): \(String(reflecting: error))"
            )
            return HistoricalValuationResult(
                key: result.key,
                diagnosticPartialTotal: result.diagnosticPartialTotal,
                finality: .closed,
                quality: .unavailable,
                publication: .unpublished,
                scopeReadiness: result.scopeReadiness,
                readinessToken: result.readinessToken,
                expectedContributionCount: result.expectedContributionCount + 1,
                resolvedContributionCount: result.resolvedContributionCount,
                unresolved: result.unresolved + [.init(
                    opaqueAccountID: "scope",
                    dimension: .cache,
                    reasonCode: "close_repository_failed"
                )],
                resolutions: result.resolutions,
                generatedAt: result.generatedAt
            )
        }
    }
}

@MainActor
protocol HistoricalPortfolioValuating: AnyObject {
    func availableAccountIDs() async -> Set<UUID>?
    func valuationBatch(
        at date: Date,
        displayCurrency: String,
        scopeID: String,
        accountIDs: Set<UUID>?,
        timeContext: HistoricalValuationTimeContext,
        clock: any HistoricalValuationClock,
        valuationPolicyVersion: Int
    ) async -> HistoricalPortfolioValuationBatch
}

struct HistoricalPortfolioValuationBatch {
    let portfolio: HistoricalValuationResult
    let accountContributions: [HistoricalPortfolioAccountContribution]
}

extension HistoricalPortfolioValuating {
    func availableAccountIDs() async -> Set<UUID>? { nil }
}

/// Optional compatibility-domain input owned by the producer. A migrated legacy predecessor may
/// contribute only through this structured boundary; callers cannot turn an old bare total into a
/// portfolio result. Returning `nil` means that the boundary is unresolved and therefore incomplete.
@MainActor
protocol HistoricalPortfolioExternalCoverageProviding: AnyObject {
    func prepare(
        for query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext,
        now: Date
    )
    func finishQuery()

    func contributions(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> [HistoricalPortfolioAccountContribution]?

    /// Requested identities which are proven not to participate at this point (for example, a
    /// migrated predecessor after its strict cutoff). They are neither zero-valued contributions
    /// nor unresolved coverage and therefore do not duplicate the successor's logical count.
    func nonParticipatingAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<String>

    /// Core successors replaced by a verified predecessor at this point. The producer removes them
    /// before aggregate and slice valuation, so one logical account contributes exactly once.
    func replacedCoreAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<UUID>
}

extension HistoricalPortfolioExternalCoverageProviding {
    func prepare(
        for query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext,
        now: Date
    ) {}

    func finishQuery() {}

    func nonParticipatingAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<String> { [] }

    func replacedCoreAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<UUID> { [] }
}

extension AccountsTotalsService: HistoricalPortfolioValuating {
    func availableAccountIDs() async -> Set<UUID>? {
        availableHistoricalAccountIDs()
    }

    func valuationBatch(
        at date: Date,
        displayCurrency: String,
        scopeID: String,
        accountIDs: Set<UUID>?,
        timeContext: HistoricalValuationTimeContext,
        clock: any HistoricalValuationClock,
        valuationPolicyVersion: Int
    ) async -> HistoricalPortfolioValuationBatch {
        await historicalValuationBatch(
            at: date,
            in: displayCurrency,
            scopeID: scopeID,
            accountIDs: accountIDs,
            timeContext: timeContext,
            clock: clock,
            valuationPolicyVersion: valuationPolicyVersion
        )
    }
}

/// The only composition boundary allowed to turn historical valuations into a UI/export series.
/// It evaluates portfolio and per-account slices for identical dates, currency, timezone and policy.
@MainActor
final class HistoricalPortfolioSeriesProducer {
    private let valuator: any HistoricalPortfolioValuating
    private let scopeID: String
    private let clock: any HistoricalValuationClock
    private let closeStore: (any HistoricalValuationClosing)?
    private let externalCoverage: (any HistoricalPortfolioExternalCoverageProviding)?

    init(
        valuator: any HistoricalPortfolioValuating,
        scopeID: String,
        clock: any HistoricalValuationClock = SystemHistoricalValuationClock(),
        closeStore: (any HistoricalValuationClosing)? = nil,
        externalCoverage: (any HistoricalPortfolioExternalCoverageProviding)? = nil
    ) {
        self.valuator = valuator
        self.scopeID = scopeID
        self.clock = clock
        self.closeStore = closeStore
        self.externalCoverage = externalCoverage
    }

    func series(for query: HistoricalPortfolioSeriesQuery) async -> HistoricalPortfolioSeriesResult {
        guard let timeContext = HistoricalValuationTimeContext(ianaTimeZoneID: query.timeZoneID) else {
            return HistoricalPortfolioSeriesResult(query: query, points: [], generatedAt: clock.now)
        }
        let dates = sampledDates(query: query, timeContext: timeContext)
        let usesExternalCoverage = !query.unresolvedExternalAccountIDs.isEmpty && externalCoverage != nil
        if usesExternalCoverage {
            externalCoverage?.prepare(for: query, timeContext: timeContext, now: clock.now)
        }
        defer {
            if usesExternalCoverage { externalCoverage?.finishQuery() }
        }
        let accountIDs: Set<UUID>?
        switch query.accountScope {
        case .portfolio: accountIDs = nil
        case .accountIDs(let ids): accountIDs = ids
        }

        var points: [HistoricalPortfolioSeriesPoint] = []
        points.reserveCapacity(dates.count)
        for date in dates {
            let replacedCoreIDs = await externalCoverage?.replacedCoreAccountIDs(
                at: date, query: query, timeContext: timeContext
            ) ?? []
            let resolvedCoreIDs: Set<UUID>?
            let coreScopeResolved: Bool
            if let accountIDs {
                resolvedCoreIDs = accountIDs.subtracting(replacedCoreIDs)
                coreScopeResolved = true
            } else if replacedCoreIDs.isEmpty {
                resolvedCoreIDs = nil
                coreScopeResolved = true
            } else if let available = await valuator.availableAccountIDs() {
                resolvedCoreIDs = available.subtracting(replacedCoreIDs)
                coreScopeResolved = true
            } else {
                resolvedCoreIDs = nil
                coreScopeResolved = false
            }
            let coreBatch = await valuator.valuationBatch(
                at: date,
                displayCurrency: query.displayCurrency,
                scopeID: scopeID,
                accountIDs: resolvedCoreIDs,
                timeContext: timeContext,
                clock: clock,
                valuationPolicyVersion: query.valuationPolicyVersion
            )
            var external = await externalContributions(at: date, query: query, timeContext: timeContext)
            if !coreScopeResolved {
                external.unresolvedIDs.insert("core_scope")
            }
            let scopedPortfolio = merging(external: external, into: coreBatch.portfolio)
            let portfolio = if let closeStore {
                await closeStore.closeIfNeeded(scopedPortfolio, publishedAt: clock.now)
            } else {
                scopedPortfolio
            }
            var contributions = external.resolved
            contributions.append(contentsOf: coreBatch.accountContributions)
            points.append(.init(
                id: HistoricalPortfolioPointID(portfolio.key),
                date: date,
                valuation: portfolio,
                accountContributions: contributions
            ))
        }
        return .init(query: query, points: points, generatedAt: clock.now)
    }

    private func externalContributions(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> (resolved: [HistoricalPortfolioAccountContribution], unresolvedIDs: Set<String>) {
        guard !query.unresolvedExternalAccountIDs.isEmpty else { return ([], []) }
        let nonParticipating = await externalCoverage?.nonParticipatingAccountIDs(
            at: date,
            query: query,
            timeContext: timeContext
        ) ?? []
        let participatingRequested = query.unresolvedExternalAccountIDs.subtracting(nonParticipating)
        guard !participatingRequested.isEmpty else { return ([], []) }
        guard let supplied = await externalCoverage?.contributions(
            at: date,
            query: query,
            timeContext: timeContext
        ) else { return ([], participatingRequested) }
        let requested = participatingRequested
        let unique = Dictionary(supplied.map { ($0.opaqueAccountID, $0) }, uniquingKeysWith: { first, _ in first })
        let resolved = requested.sorted().compactMap { unique[$0] }
        return (resolved, requested.subtracting(Set(unique.keys)))
    }

    private func merging(
        external: (resolved: [HistoricalPortfolioAccountContribution], unresolvedIDs: Set<String>),
        into result: HistoricalValuationResult
    ) -> HistoricalValuationResult {
        let resolvedValues = external.resolved.compactMap(\.value)
        let externalUnresolved = external.resolved.flatMap(\.unresolved)
        let missing = external.unresolvedIDs.sorted().map {
            HistoricalValuationUnresolvedContribution(
                opaqueAccountID: $0,
                dimension: .migrationBoundary,
                reasonCode: "legacy_boundary_unresolved"
            )
        }
        let resolvedCount = external.resolved.filter { $0.value != nil && $0.state != .incomplete }.count
        let expectedCount = external.resolved.count + external.unresolvedIDs.count
        let key = keyIncludingExternalEvidence(result.key, external: external)
        return HistoricalValuationResult(
            key: key,
            diagnosticPartialTotal: result.diagnosticPartialTotal + resolvedValues.reduce(0, +),
            finality: result.finality,
            quality: mergedQuality(core: result.quality, external: external.resolved),
            publication: result.publication,
            scopeReadiness: result.scopeReadiness,
            readinessToken: result.readinessToken,
            expectedContributionCount: result.expectedContributionCount + expectedCount,
            resolvedContributionCount: result.resolvedContributionCount + resolvedCount,
            unresolved: result.unresolved + externalUnresolved + missing,
            resolutions: result.resolutions + external.resolved.flatMap(\.resolutions),
            generatedAt: result.generatedAt
        )
    }

    private func keyIncludingExternalEvidence(
        _ key: HistoricalValuationKey,
        external: (resolved: [HistoricalPortfolioAccountContribution], unresolvedIDs: Set<String>)
    ) -> HistoricalValuationKey {
        var digest = key.inputRevision.evidence
        let tokens = external.resolved.map {
            "\($0.opaqueAccountID)|\($0.value?.description ?? "nil")|\($0.state)|\($0.quality)"
        } + external.unresolvedIDs.map { "\($0)|unresolved" }
        for byte in tokens.sorted().joined(separator: "\u{1F}").utf8 {
            digest = (digest ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return HistoricalValuationKey(
            schemaVersion: key.schemaVersion,
            scopeID: key.scopeID,
            dayKey: key.dayKey,
            timeZoneID: key.timeZoneID,
            displayCurrency: key.displayCurrency,
            valuationPolicyVersion: key.valuationPolicyVersion,
            inputRevision: .init(
                accountSet: key.inputRevision.accountSet,
                financial: key.inputRevision.financial,
                events: key.inputRevision.events,
                evidence: digest
            )
        )
    }

    private func mergedQuality(
        core: HistoricalValuationQuality,
        external: [HistoricalPortfolioAccountContribution]
    ) -> HistoricalValuationQuality {
        guard !external.isEmpty else { return core }
        let qualities = Set(external.map(\.quality)).union([core])
        return qualities.count == 1 ? core : .mixed
    }

    private func addingExternalCoverageFailures(
        _ opaqueAccountIDs: Set<String>,
        to result: HistoricalValuationResult
    ) -> HistoricalValuationResult {
        guard !opaqueAccountIDs.isEmpty else { return result }
        let missing = opaqueAccountIDs.sorted().map {
            HistoricalValuationUnresolvedContribution(
                opaqueAccountID: $0,
                dimension: .migrationBoundary,
                reasonCode: "legacy_boundary_unresolved"
            )
        }
        return HistoricalValuationResult(
            key: result.key,
            diagnosticPartialTotal: result.diagnosticPartialTotal,
            finality: result.finality,
            quality: .unavailable,
            publication: result.publication,
            scopeReadiness: result.scopeReadiness,
            readinessToken: result.readinessToken,
            expectedContributionCount: result.expectedContributionCount + missing.count,
            resolvedContributionCount: result.resolvedContributionCount,
            unresolved: result.unresolved + missing,
            resolutions: result.resolutions,
            generatedAt: result.generatedAt
        )
    }

    private func sampledDates(
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) -> [Date] {
        let start = min(query.period.start, query.period.end)
        let end = max(query.period.start, query.period.end)
        switch query.samplingPolicy {
        case .exact(let dates):
            return Array(Set(dates.filter { $0 >= start && $0 <= end })).sorted()
        case .daily:
            if start == end { return [start] }
            var result = [start]
            var cursor = timeContext.startOfDay(for: start)
            while let next = Calendar.gregorian(in: timeContext.timeZone).date(byAdding: .day, value: 1, to: cursor),
                  next < timeContext.startOfDay(for: end) {
                result.append(timeContext.endOfDay(for: next))
                cursor = next
            }
            result.append(end)
            return result
        }
    }
}

private extension Calendar {
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }
}
