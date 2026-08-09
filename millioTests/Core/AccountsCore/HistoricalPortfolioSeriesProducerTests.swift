import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("Historical portfolio series producer")
struct HistoricalPortfolioSeriesProducerTests {
    @Test("incomplete closed result keeps root cause and is not sent to close repository")
    func incompleteResultIsNotPublished() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let unresolvedID = UUID()
        let result = await HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:], unresolvedIDs: [unresolvedID]),
            scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400)),
            closeStore: HistoricalValuationCloseStore(modelContainer: container)
        ).series(for: .init(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            accountScope: .accountIDs([unresolvedID]),
            samplingPolicy: .exact([date])
        ))

        let point = try #require(result.points.first)
        #expect(point.valuation.total == nil)
        #expect(point.valuation.unresolved.map(\.reasonCode) == ["fixture_missing_fx"])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<HistoricalPortfolioValuation>()) == 0)
    }

    @Test("portfolio and account slices keep one point identity contract")
    func pointAndSlicesShareQueryIdentity() async throws {
        let accountA = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let accountB = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let end = start.addingTimeInterval(86_400 * 2)
        let clock = FixedClock(now: end.addingTimeInterval(86_400))
        let valuator = FakeValuator(values: [accountA: 40, accountB: 60])
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: valuator,
            scopeID: "guest",
            clock: clock
        )
        let query = HistoricalPortfolioSeriesQuery(
            period: DateInterval(start: start, end: end),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "rub",
            accountScope: .accountIDs([accountA, accountB]),
            samplingPolicy: .exact([start, end]),
            valuationPolicyVersion: 7
        )

        let result = await producer.series(for: query)

        #expect(result.points.count == 2)
        #expect(result.points.allSatisfy { $0.valuation.total == 100 })
        #expect(result.points.allSatisfy { $0.accountContributions.count == 2 })
        #expect(result.points.allSatisfy { point in
            point.id.dayKey == point.valuation.key.dayKey
                && point.id.timeZoneID == "Europe/Istanbul"
                && point.id.displayCurrency == "RUB"
                && point.id.valuationPolicyVersion == 7
        })
        #expect(valuator.calls.count == 2)
        #expect(valuator.calls.allSatisfy { $0.timeZoneID == "Europe/Istanbul" && $0.currency == "RUB" })
    }

    @Test("series performs one structured core pass per point, independent of account count")
    func coreValuationIsBatchedPerPoint() async {
        let accounts = Dictionary(uniqueKeysWithValues: (0..<24).map { _ in (UUID(), Decimal(1)) })
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let dates = (0..<30).map { start.addingTimeInterval(Double($0) * 86_400) }
        let valuator = FakeValuator(values: accounts)
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: valuator,
            scopeID: "perf",
            clock: FixedClock(now: dates.last!.addingTimeInterval(86_400))
        )
        let measured = await ContinuousClock().measure {
            _ = await producer.series(for: .init(
                period: DateInterval(start: dates.first!, end: dates.last!),
                timeZoneID: "Europe/Istanbul",
                displayCurrency: "USD",
                accountScope: .accountIDs(Set(accounts.keys)),
                samplingPolicy: .exact(dates)
            ))
        }

        // Behavioral budget is the hard contract: the old N+1 path made 750 calls here.
        #expect(valuator.calls.count == dates.count)
        #expect(valuator.calls.allSatisfy { $0.accountCount == accounts.count })
        // Baseline is intentionally not invented before the first authorized simulator run.
        // The 1 s ceiling is a coarse regression alarm; call count is the stable performance contract.
        #expect(measured < .seconds(1))
    }

    @Test("external evidence lifecycle is prepared once per multi-point query")
    func externalEvidenceIsCachedPerQuery() async {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let dates = (0..<12).map { start.addingTimeInterval(Double($0) * 86_400) }
        let external = FakeExternalCoverage(values: ["legacy": 2])
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:]),
            scopeID: "perf",
            clock: FixedClock(now: dates.last!.addingTimeInterval(86_400)),
            externalCoverage: external
        )

        _ = await producer.series(for: .init(
            period: DateInterval(start: dates.first!, end: dates.last!),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "USD",
            samplingPolicy: .exact(dates),
            unresolvedExternalAccountIDs: ["legacy"]
        ))

        #expect(external.prepareCount == 1)
        #expect(external.contributionCount == dates.count)
        #expect(external.finishCount == 1)
    }

    @Test("incomplete contribution remains nil and is never diagnostic subtotal")
    func incompleteIsNotPublishedAsNumericPoint() async {
        let account = UUID()
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let valuator = FakeValuator(values: [:], unresolvedIDs: [account])
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: valuator,
            scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400))
        )
        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "USD",
            accountScope: .accountIDs([account]),
            samplingPolicy: .exact([date])
        ))

        let point = result.points.first
        #expect(point?.valuation.total == nil)
        #expect(point?.valuation.diagnosticPartialTotal == 0)
        #expect(point?.valuation.state == .incomplete)
        #expect(point?.accountContributions.first?.value == nil)
    }

    @Test("shadow deltas disclose only a bucket")
    func shadowDeltaBuckets() {
        #expect(HistoricalPortfolioShadowDeltaBucket.classify(structured: 100, compatibility: 100) == .exact)
        #expect(HistoricalPortfolioShadowDeltaBucket.classify(structured: 100.5, compatibility: 100) == .underOnePercent)
        #expect(HistoricalPortfolioShadowDeltaBucket.classify(structured: 103, compatibility: 100) == .underFivePercent)
        #expect(HistoricalPortfolioShadowDeltaBucket.classify(structured: 90, compatibility: 100) == .fivePercentOrMore)
        #expect(HistoricalPortfolioShadowDeltaBucket.classify(structured: nil, compatibility: 100) == .unavailable)
    }

    @Test("unresolved legacy boundary invalidates every public point total")
    func unresolvedExternalCoverageIsIncomplete() async {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:]),
            scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400))
        )

        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact([date]),
            unresolvedExternalAccountIDs: ["opaque-legacy-1"]
        ))

        #expect(result.points.first?.valuation.total == nil)
        #expect(result.points.first?.valuation.state == .incomplete)
        #expect(result.points.first?.valuation.unresolved.first?.dimension == .migrationBoundary)
        #expect(result.points.first?.valuation.unresolved.first?.reasonCode == "legacy_boundary_unresolved")
    }

    @Test("verified legacy predecessor is merged once instead of failing a valid old window")
    func verifiedLegacyPredecessorCompletesCoverage() async {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let legacyID = "legacy-card"
        let provider = FakeExternalCoverage(values: [legacyID: 25])
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:]),
            scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400)),
            externalCoverage: provider
        )

        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact([date]),
            unresolvedExternalAccountIDs: [legacyID]
        ))

        #expect(result.points.first?.valuation.total == 25)
        #expect(result.points.first?.valuation.state == .complete)
        #expect(result.points.first?.accountContributions.map(\.opaqueAccountID) == [legacyID])
    }

    @Test("external provider cannot silently omit a requested predecessor")
    func partialExternalCoverageFailsClosed() async {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:]),
            scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400)),
            externalCoverage: FakeExternalCoverage(values: ["known": 25])
        )
        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date), timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB", samplingPolicy: .exact([date]),
            unresolvedExternalAccountIDs: ["known", "missing"]
        ))

        #expect(result.points.first?.valuation.total == nil)
        #expect(result.points.first?.valuation.diagnosticPartialTotal == 25)
        #expect(result.points.first?.valuation.unresolved.contains { $0.opaqueAccountID == "missing" } == true)
    }

    @Test("proven predecessor after cutoff is not counted as zero beside its successor")
    func nonParticipatingPredecessorDoesNotDuplicateLogicalCount() async {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let coreID = UUID()
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [coreID: 40]), scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400)),
            externalCoverage: FakeExternalCoverage(values: ["legacy": 25], nonParticipating: ["legacy"])
        )
        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date), timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB", accountScope: .accountIDs([coreID]),
            samplingPolicy: .exact([date]), unresolvedExternalAccountIDs: ["legacy"]
        ))

        #expect(result.points.first?.valuation.total == 40)
        #expect(result.points.first?.valuation.expectedContributionCount == 1)
        #expect(result.points.first?.accountContributions.map(\.opaqueAccountID) == [coreID.uuidString])
    }

    @Test("verified predecessor replaces resolved-zero successor before cutoff")
    func predecessorReplacesCoreBeforeCutoff() async {
        let date = Date(timeIntervalSince1970: 1_767_225_600)
        let coreID = UUID()
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [coreID: 0]), scopeID: "guest",
            clock: FixedClock(now: date.addingTimeInterval(86_400)),
            externalCoverage: FakeExternalCoverage(values: ["legacy": 25], replacedCoreIDs: [coreID])
        )
        let result = await producer.series(for: .init(
            period: DateInterval(start: date, end: date), timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB", accountScope: .accountIDs([coreID]),
            samplingPolicy: .exact([date]), unresolvedExternalAccountIDs: ["legacy"]
        ))

        #expect(result.points.first?.valuation.total == 25)
        #expect(result.points.first?.valuation.expectedContributionCount == 1)
        #expect(result.points.first?.accountContributions.map(\.opaqueAccountID) == ["legacy"])
    }

    @Test("every requested closed point is offered to the lazy close store sequentially")
    func lazyCloseCoversMultiDayGap() async {
        let start = Date(timeIntervalSince1970: 1_767_225_600)
        let end = start.addingTimeInterval(86_400 * 2)
        let closer = FakeCloser()
        let producer = HistoricalPortfolioSeriesProducer(
            valuator: FakeValuator(values: [:]),
            scopeID: "guest",
            clock: FixedClock(now: end.addingTimeInterval(86_400)),
            closeStore: closer
        )

        let result = await producer.series(for: .init(
            period: DateInterval(start: start, end: end),
            timeZoneID: "Europe/Istanbul",
            displayCurrency: "RUB",
            samplingPolicy: .exact([start, start.addingTimeInterval(86_400), end])
        ))

        #expect(result.points.count == 3)
        #expect(closer.dayKeys == result.points.map(\.valuation.key.dayKey))
    }
}

private struct FixedClock: HistoricalValuationClock {
    let now: Date
}

@MainActor
private final class FakeValuator: HistoricalPortfolioValuating {
    struct Call {
        let currency: String
        let timeZoneID: String
        let accountCount: Int?
    }

    private let values: [UUID: Decimal]
    private let unresolvedIDs: Set<UUID>
    private(set) var calls: [Call] = []

    init(values: [UUID: Decimal], unresolvedIDs: Set<UUID> = []) {
        self.values = values
        self.unresolvedIDs = unresolvedIDs
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
        calls.append(.init(
            currency: displayCurrency,
            timeZoneID: timeContext.timeZoneID,
            accountCount: accountIDs?.count
        ))
        let ids = accountIDs ?? Set(values.keys).union(unresolvedIDs)
        let unresolved = ids.intersection(unresolvedIDs).map {
            HistoricalValuationUnresolvedContribution(
                opaqueAccountID: $0.uuidString,
                dimension: .fxRate,
                reasonCode: "fixture_missing_fx"
            )
        }
        let total = ids.compactMap { values[$0] }.reduce(0, +)
        let resolved = ids.count - unresolved.count
        let portfolio = HistoricalValuationResult(
            key: .init(
                schemaVersion: 7,
                scopeID: scopeID,
                dayKey: timeContext.dayKey(for: date),
                timeZoneID: timeContext.timeZoneID,
                displayCurrency: displayCurrency,
                valuationPolicyVersion: valuationPolicyVersion,
                inputRevision: .init(accountSet: 1, financial: 2, events: 3, evidence: 4)
            ),
            diagnosticPartialTotal: total,
            finality: .closed,
            quality: unresolved.isEmpty ? .exact : .unavailable,
            expectedContributionCount: ids.count,
            resolvedContributionCount: resolved,
            unresolved: unresolved,
            resolutions: [],
            generatedAt: clock.now
        )
        let contributions = ids.sorted { $0.uuidString < $1.uuidString }.map { id in
            let missing = unresolved.filter { $0.opaqueAccountID == id.uuidString }
            return HistoricalPortfolioAccountContribution(
                opaqueAccountID: id.uuidString,
                value: missing.isEmpty ? values[id] : nil,
                state: missing.isEmpty ? .complete : .incomplete,
                quality: missing.isEmpty ? .exact : .unavailable,
                unresolved: missing
            )
        }
        return .init(portfolio: portfolio, accountContributions: contributions)
    }
}

@MainActor
private final class FakeCloser: HistoricalValuationClosing {
    private(set) var dayKeys: [String] = []

    func closeIfNeeded(
        _ result: HistoricalValuationResult,
        publishedAt: Date
    ) async -> HistoricalValuationResult {
        dayKeys.append(result.key.dayKey)
        return result
    }
}

@MainActor
private final class FakeExternalCoverage: HistoricalPortfolioExternalCoverageProviding {
    let values: [String: Decimal]
    let nonParticipating: Set<String>
    let replacedCoreIDs: Set<UUID>
    private(set) var prepareCount = 0
    private(set) var contributionCount = 0
    private(set) var finishCount = 0
    init(
        values: [String: Decimal],
        nonParticipating: Set<String> = [],
        replacedCoreIDs: Set<UUID> = []
    ) {
        self.values = values
        self.nonParticipating = nonParticipating
        self.replacedCoreIDs = replacedCoreIDs
    }

    func prepare(
        for query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext,
        now: Date
    ) {
        prepareCount += 1
    }

    func finishQuery() {
        finishCount += 1
    }

    func contributions(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> [HistoricalPortfolioAccountContribution]? {
        contributionCount += 1
        return values.filter { !nonParticipating.contains($0.key) }.map { entry -> HistoricalPortfolioAccountContribution in
            HistoricalPortfolioAccountContribution(
                opaqueAccountID: entry.key,
                value: entry.value,
                state: .complete,
                quality: .exact,
                unresolved: []
            )
        }
    }

    func nonParticipatingAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<String> { nonParticipating }

    func replacedCoreAccountIDs(
        at date: Date,
        query: HistoricalPortfolioSeriesQuery,
        timeContext: HistoricalValuationTimeContext
    ) async -> Set<UUID> { replacedCoreIDs }
}
