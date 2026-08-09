import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Accounts totals structured historical boundary")
struct AccountsTotalsHistoricalValuationTests {
    private enum InjectedFailure: Error { case expected }

    private struct FixedClock: HistoricalValuationClock {
        let now: Date
    }

    private actor EvidenceProvider: HistoricalValuationEvidenceProviding {
        let fx: [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle]
        let market: [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle]

        init(
            fx: [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] = [:],
            market: [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] = [:]
        ) {
            self.fx = fx
            self.market = market
        }

        func fetchFXEvidence(
            for dependencies: Set<HistoricalFXDependencyKey>
        ) async throws -> [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] {
            fx.filter { dependencies.contains($0.key) }
        }

        func fetchMarketEvidence(
            for dependencies: Set<HistoricalMarketDependencyKey>
        ) async throws -> [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] {
            market.filter { dependencies.contains($0.key) }
        }
    }

    private struct DayPriceProvider: MarketPriceProviding {
        let timeContext: HistoricalValuationTimeContext
        let prices: [String: Decimal]

        func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal? {
            prices[timeContext.dayKey(for: date)]
        }
    }

    @MainActor private static var retainedContainers: [ModelContainer] = []

    @MainActor
    private func makeStack(
        access: HistoricalValuationDataAccess,
        readiness: @escaping @MainActor () -> HistoricalScopeReadiness = { .ready },
        rateService: CurrencyRateServiceProtocol? = nil,
        evidenceProvider: (any HistoricalValuationEvidenceProviding)? = nil
    ) throws -> AccountsTotalsService {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return AccountsTotalsService(
            modelContext: container.mainContext,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: rateService ?? DateAwareMockRateService(),
            historicalDataAccess: access,
            historicalEvidenceProvider: evidenceProvider,
            scopeReadiness: readiness
        )
    }

    @MainActor
    private func access(
        account: Account,
        events: @escaping @MainActor () throws -> [AccountEvent],
        rebuild: @escaping @MainActor (Account, Date, MarketPriceProviding?) async throws -> Void = { _, _, _ in },
        snapshot: @escaping @MainActor (Account, String) throws -> AccountDailySnapshot? = { _, _ in nil }
    ) -> HistoricalValuationDataAccess {
        HistoricalValuationDataAccess(
            fetchAccounts: { [account] },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: rebuild,
            fetchLatestSnapshot: snapshot,
            fetchEvents: { _ in try events() }
        )
    }

    @Test @MainActor
    func readyEmptyScopeIsUnpublishedZeroButFailedAccountFetchIsIncomplete() async throws {
        let readyAccess = HistoricalValuationDataAccess(
            fetchAccounts: { [] },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { _ in [] }
        )
        let failedAccess = HistoricalValuationDataAccess(
            fetchAccounts: { throw InjectedFailure.expected },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { _ in [] }
        )
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)

        let ready = try await makeStack(access: readyAccess).historicalValuation(
            at: instant, in: "RUB", scopeID: "guest", timeContext: time,
            clock: FixedClock(now: instant.addingTimeInterval(86_400))
        )
        let failed = try await makeStack(access: failedAccess).historicalValuation(
            at: instant, in: "RUB", scopeID: "guest", timeContext: time,
            clock: FixedClock(now: instant.addingTimeInterval(86_400))
        )

        #expect(ready.total == 0)
        #expect(ready.state == .provisional)
        #expect(ready.publication == .unpublished)
        #expect(failed.total == nil)
        #expect(failed.state == .incomplete)
        #expect(failed.unresolved.map(\.dimension) == [.accountData])
    }

    @Test @MainActor
    func restoreReconciliationAndBackfillBlockPublicationBeforeFetch() async throws {
        let access = HistoricalValuationDataAccess(
            fetchAccounts: { Issue.record("Non-ready scope must short-circuit before fetch"); return [] },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { _ in [] }
        )
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)

        for readiness in [
            HistoricalScopeReadiness.restoring,
            .reconciling,
            .backfilling,
            .failed(reasonCode: "restore_partial")
        ] {
            let service = try makeStack(access: access, readiness: { readiness })
            let result = await service.historicalValuation(
                at: instant, in: "RUB", scopeID: "guest", timeContext: time,
                clock: FixedClock(now: instant.addingTimeInterval(86_400))
            )
            #expect(result.total == nil)
            #expect(result.state == .incomplete)
            #expect(result.scopeReadiness == readiness)
            #expect(result.unresolved.map(\.dimension) == [.scopeReadiness])
        }
    }

    @Test @MainActor
    func eventRebuildAndSnapshotFetchFailuresStayTypedAndNeverBecomeZero() async throws {
        let account = Account(
            name: "Opaque", kind: .cash, currency: "RUB", createdAt: .distantPast
        )
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let clock = FixedClock(now: instant.addingTimeInterval(86_400))

        let cases: [(HistoricalValuationDataAccess, HistoricalValuationMissingDimension, String)] = [
            (
                access(account: account, events: { throw InjectedFailure.expected }),
                .events,
                "event_fetch_failed"
            ),
            (
                access(
                    account: account,
                    events: { [] },
                    rebuild: { _, _, _ in throw InjectedFailure.expected }
                ),
                .nativeBalance,
                "snapshot_rebuild_failed"
            ),
            (
                access(
                    account: account,
                    events: { [] },
                    snapshot: { _, _ in throw InjectedFailure.expected }
                ),
                .cache,
                "snapshot_fetch_failed"
            )
        ]

        for (access, dimension, reason) in cases {
            let result = try await makeStack(access: access).historicalValuation(
                at: instant, in: "RUB", scopeID: "guest", timeContext: time, clock: clock
            )
            #expect(result.total == nil)
            #expect(result.diagnosticPartialTotal == 0)
            #expect(result.unresolved.map(\.dimension) == [dimension])
            #expect(result.unresolved.map(\.reasonCode) == [reason])
        }
    }

    @Test @MainActor
    func corruptedSnapshotInvalidNativeValueAndMissingMarketPriceStayIncomplete() async throws {
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let clock = FixedClock(now: instant.addingTimeInterval(86_400))

        let cachedAccount = Account(name: "Cache", kind: .cash, currency: "RUB", createdAt: .distantPast)
        let corruptedSnapshot = AccountDailySnapshot(
            account: cachedAccount, dayKey: "2026-99-99", balance: 1, isClosed: false
        )
        let cacheResult = try await makeStack(
            access: access(
                account: cachedAccount,
                events: { [AccountEvent(account: cachedAccount, date: .distantPast, type: .openingBalance, amount: 1)] },
                snapshot: { _, _ in corruptedSnapshot }
            )
        ).historicalValuation(at: instant, in: "RUB", scopeID: "guest", timeContext: time, clock: clock)

        let invalidAccount = Account(name: "NaN", kind: .cash, currency: "RUB", createdAt: .distantPast)
        let invalidResult = try await makeStack(
            access: access(
                account: invalidAccount,
                events: { [AccountEvent(account: invalidAccount, date: .distantPast, type: .openingBalance, amount: .nan)] }
            )
        ).historicalValuation(at: instant, in: "RUB", scopeID: "guest", timeContext: time, clock: clock)

        let market = Account(name: "Market", kind: .marketInvestment, currency: "RUB", createdAt: .distantPast)
        market.marketMeta = MarketMeta(symbol: "MISS", assetClass: .stock)
        let missingPriceResult = try await makeStack(
            access: access(
                account: market,
                events: { [AccountEvent(account: market, date: .distantPast, type: .buy, quantity: 1)] }
            )
        ).historicalValuation(at: instant, in: "RUB", scopeID: "guest", timeContext: time, clock: clock)

        #expect(cacheResult.total == nil)
        #expect(cacheResult.unresolved.map(\.reasonCode) == ["snapshot_cache_corrupted"])
        #expect(invalidResult.total == nil)
        #expect(invalidResult.unresolved.map(\.reasonCode) == ["invalid_native_value"])
        #expect(missingPriceResult.total == nil)
        #expect(missingPriceResult.unresolved.map(\.dimension) == [.marketPrice])
    }

    @Test @MainActor
    func emptyScopePriceCacheFailureIsNotACompleteZero() async throws {
        let dataAccess = HistoricalValuationDataAccess(
            fetchAccounts: { [] },
            makeMarketPriceProvider: { _ in throw InjectedFailure.expected },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { _ in [] }
        )
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let result = try await makeStack(access: dataAccess).historicalValuation(
            at: instant,
            in: "RUB",
            scopeID: "guest",
            timeContext: time,
            clock: FixedClock(now: instant.addingTimeInterval(86_400))
        )

        #expect(result.total == nil)
        #expect(result.state == .incomplete)
        #expect(result.unresolved.map(\.dimension) == [.cache])
    }

    @Test @MainActor
    func structuredBoundaryDirectReplayMatchesStartMiddleAndEndDespiteSameDaySnapshot() async throws {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let time = HistoricalValuationTimeContext(timeZone: timeZone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = Date(timeIntervalSince1970: 1_704_067_200)
        let account = Account(name: "Opaque", kind: .cash, currency: "RUB", createdAt: dayStart)
        let opening = AccountEvent(
            account: account,
            date: calendar.date(byAdding: .hour, value: 9, to: dayStart)!,
            type: .openingBalance,
            amount: 100
        )
        let income = AccountEvent(
            account: account,
            date: calendar.date(byAdding: .hour, value: 18, to: dayStart)!,
            type: .income,
            amount: 50
        )
        let events = [opening, income]
        let sameDaySnapshot = AccountDailySnapshot(
            account: account, dayKey: "2024-01-01", balance: 150, isClosed: false
        )
        let dataAccess = access(
            account: account,
            events: { events },
            snapshot: { _, _ in sameDaySnapshot }
        )
        let service = try makeStack(access: dataAccess)
        let instants = [
            dayStart,
            calendar.date(byAdding: .hour, value: 12, to: dayStart)!,
            calendar.date(byAdding: .second, value: -1, to: calendar.date(byAdding: .day, value: 1, to: dayStart)!)!
        ]

        for instant in instants {
            let result = await service.historicalValuation(
                at: instant, in: "RUB", scopeID: "guest", timeContext: time,
                clock: FixedClock(now: dayStart.addingTimeInterval(2 * 86_400))
            )
            let direct = AccountBalanceEngine.balanceAt(events: events, kind: .cash, on: instant)
            #expect(result.total == direct)
            if direct == 0 {
                #expect(result.resolutions.first?.opaqueAccountID == account.id.uuidString)
                #expect(result.resolutions.first?.kind == "provenZero")
                #expect(result.resolutions.first?.sourceID == nil)
            }
        }
    }

    @Test @MainActor
    func exactFixtureUsesSameFrozenDayAt2359And0001WithoutPublishing77Million() async throws {
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = time.timeZone
        let dayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 8)))
        let query = dayStart.addingTimeInterval(12 * 3_600)
        let base = Account(name: "Base", kind: .cash, currency: "RUB", createdAt: dayStart.addingTimeInterval(-1))
        let foreign = Account(name: "Foreign", kind: .cash, currency: "USD", createdAt: dayStart.addingTimeInterval(-1))
        let eventsByID: [UUID: [AccountEvent]] = [
            base.id: [AccountEvent(account: base, date: dayStart, type: .openingBalance, amount: 77_125_067)],
            foreign.id: [AccountEvent(account: foreign, date: dayStart, type: .openingBalance, amount: 22_507_974)]
        ]
        let dataAccess = HistoricalValuationDataAccess(
            fetchAccounts: { [base, foreign] },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { eventsByID[$0.id] ?? [] }
        )
        let rates = DateAwareMockRateService()
        rates.todayRate = 1
        let fxKey = HistoricalFXDependencyKey(
            dayKey: "2026-08-08",
            pair: .init(base: "USD", quote: "RUB")
        )
        let currentEvidence = HistoricalValuationEvidenceRecord(
            value: 1,
            dayKey: "2026-08-08",
            recordID: "fixture-current",
            sourceID: "fixture",
            observedAt: dayStart.addingTimeInterval(12 * 3_600)
        )
        let service = try makeStack(
            access: dataAccess,
            rateService: rates,
            evidenceProvider: EvidenceProvider(fx: [
                fxKey: .init(currentEstimate: [currentEvidence])
            ])
        )

        let at2359 = await service.historicalValuation(
            at: query,
            in: "RUB",
            scopeID: "guest",
            timeContext: time,
            clock: FixedClock(now: dayStart.addingTimeInterval(23 * 3_600 + 59 * 60))
        )
        let at0001 = await service.historicalValuation(
            at: query,
            in: "RUB",
            scopeID: "guest",
            timeContext: time,
            clock: FixedClock(now: dayStart.addingTimeInterval(24 * 3_600 + 60))
        )

        #expect(at2359.key.dayKey == "2026-08-08")
        #expect(at0001.key.dayKey == "2026-08-08")
        #expect(at2359.total == 99_633_041)
        #expect(at2359.state == .provisional)
        #expect(at0001.total == nil)
        #expect(at0001.state == .incomplete)
        #expect(at0001.diagnosticPartialTotal == 77_125_067)
        #expect(at2359.diagnosticPartialTotal - at0001.diagnosticPartialTotal == 22_507_974)
        #expect(at0001.unresolved.map(\.dimension) == [.fxRate])
    }

    @Test @MainActor
    func marketReplayUsesRequestedDayPriceInsteadOfStaleSnapshotValue() async throws {
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day1 = Date(timeIntervalSince1970: 1_704_067_200)
        let day3 = day1.addingTimeInterval(2 * 86_400)
        let account = Account(
            name: "Market", kind: .marketInvestment, currency: "USD", createdAt: day1,
            includeInTotal: true
        )
        account.marketMeta = MarketMeta(symbol: "TEST", assetClass: .stock)
        let buy = AccountEvent(account: account, date: day1, type: .buy, quantity: 10, unitPrice: 50)
        let staleSnapshot = AccountDailySnapshot(
            account: account, dayKey: "2024-01-01", balance: 1_000, isClosed: false
        )
        let provider = DayPriceProvider(
            timeContext: time,
            prices: ["2024-01-01": 100, "2024-01-03": 300]
        )
        let dataAccess = HistoricalValuationDataAccess(
            fetchAccounts: { [account] },
            makeMarketPriceProvider: { _ in provider },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in staleSnapshot },
            fetchEvents: { _ in [buy] }
        )
        let instrument = HistoricalMarketInstrument(symbol: "TEST", assetClass: .stock)
        let day1Key = HistoricalMarketDependencyKey(dayKey: "2024-01-01", instrument: instrument)
        let day3Key = HistoricalMarketDependencyKey(dayKey: "2024-01-03", instrument: instrument)
        let evidenceProvider = EvidenceProvider(market: [
            day1Key: .init(exact: [.init(
                value: 100, dayKey: "2024-01-01", recordID: "price-1",
                sourceID: "fixture", observedAt: day1
            )]),
            day3Key: .init(exact: [.init(
                value: 300, dayKey: "2024-01-03", recordID: "price-3",
                sourceID: "fixture", observedAt: day3
            )])
        ])
        let service = try makeStack(access: dataAccess, evidenceProvider: evidenceProvider)

        let result1 = await service.historicalValuation(
            at: day1, in: "USD", scopeID: "guest", timeContext: time,
            clock: FixedClock(now: day3.addingTimeInterval(86_400))
        )
        let result3 = await service.historicalValuation(
            at: day3, in: "USD", scopeID: "guest", timeContext: time,
            clock: FixedClock(now: day3.addingTimeInterval(86_400))
        )

        #expect(result1.total == 1_000)
        #expect(result3.total == 3_000)
    }

    @Test @MainActor
    func crossTimezoneSnapshotDayKeyCannotOverrideTimestampReplay() async throws {
        let istanbul = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))
        let losAngeles = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "America/Los_Angeles"))
        let instant = Date(timeIntervalSince1970: 1_786_150_800)
        let account = Account(name: "Cross TZ", kind: .cash, currency: "RUB", createdAt: instant.addingTimeInterval(-1))
        let opening = AccountEvent(account: account, date: instant.addingTimeInterval(-1), type: .openingBalance, amount: 100)
        let incompatibleSnapshot = AccountDailySnapshot(
            account: account, dayKey: "2026-08-07", balance: 999, isClosed: false
        )
        let dataAccess = access(
            account: account,
            events: { [opening] },
            snapshot: { _, _ in incompatibleSnapshot }
        )
        let service = try makeStack(access: dataAccess)
        let clock = FixedClock(now: instant.addingTimeInterval(2 * 86_400))

        let resultIstanbul = await service.historicalValuation(
            at: instant, in: "RUB", scopeID: "guest", timeContext: istanbul, clock: clock
        )
        let resultLosAngeles = await service.historicalValuation(
            at: instant, in: "RUB", scopeID: "guest", timeContext: losAngeles, clock: clock
        )

        #expect(resultIstanbul.key.dayKey == "2026-08-08")
        #expect(resultLosAngeles.key.dayKey == "2026-08-07")
        #expect(resultIstanbul.total == 100)
        #expect(resultLosAngeles.total == 100)
    }

    @Test @MainActor
    func blankAndUnknownDisplayCurrenciesAndInvalidRateAreIncomplete() async throws {
        let account = Account(
            name: "Opaque", kind: .cash, currency: "USD", createdAt: .distantPast
        )
        let event = AccountEvent(account: account, date: .distantPast, type: .openingBalance, amount: 100)
        let instant = Date(timeIntervalSince1970: 1_700_000_000)
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let dayKey = time.dayKey(for: instant)
        let fxKey = HistoricalFXDependencyKey(dayKey: dayKey, pair: .init(base: "USD", quote: "RUB"))
        let invalidEvidence = HistoricalValuationEvidenceRecord(
            value: .nan,
            dayKey: dayKey,
            recordID: "invalid-rate",
            sourceID: "fixture",
            observedAt: instant
        )
        let service = try makeStack(
            access: access(account: account, events: { [event] }),
            evidenceProvider: EvidenceProvider(fx: [fxKey: .init(exact: [invalidEvidence])])
        )
        let clock = FixedClock(now: instant.addingTimeInterval(86_400))

        let badCurrency = await service.historicalValuation(
            at: instant, in: " ", scopeID: "guest", timeContext: time, clock: clock
        )
        let unknownCurrency = await service.historicalValuation(
            at: instant, in: "ZZZ", scopeID: "guest", timeContext: time, clock: clock
        )
        let badRate = await service.historicalValuation(
            at: instant, in: "RUB", scopeID: "guest", timeContext: time, clock: clock
        )

        #expect(badCurrency.total == nil)
        #expect(badCurrency.unresolved.map(\.reasonCode) == ["invalid_display_currency"])
        #expect(unknownCurrency.total == nil)
        #expect(unknownCurrency.unresolved.map(\.reasonCode) == ["invalid_display_currency"])
        #expect(badRate.total == nil)
        #expect(badRate.unresolved.map(\.reasonCode) == ["invalid_exact_value"])
    }

    @Test @MainActor
    func structuredBoundaryUsesProductionLocalEvidenceAdapterAndPreservesProvenance() async throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let context = container.mainContext
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let dayStart = Date(timeIntervalSince1970: 1_704_067_200)
        let query = dayStart.addingTimeInterval(12 * 3_600)
        let account = Account(name: "USD", kind: .cash, currency: "USD", createdAt: dayStart)
        let opening = AccountEvent(account: account, date: dayStart, type: .openingBalance, amount: 10)
        let rate = HistoricalRate(
            baseCurrency: "USD",
            quoteCurrency: "RUB",
            rate: 90,
            rateDate: dayStart,
            source: "historical|tz=GMT",
            fetchedAt: query
        )
        context.insert(rate)
        try context.save()
        let dataAccess = HistoricalValuationDataAccess(
            fetchAccounts: { [account] },
            makeMarketPriceProvider: { _ in nil },
            rebuildSnapshots: { _, _, _ in },
            fetchLatestSnapshot: { _, _ in nil },
            fetchEvents: { _ in [opening] }
        )
        let service = AccountsTotalsService(
            modelContext: context,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: DateAwareMockRateService(),
            historicalDataAccess: dataAccess
        )

        let result = await service.historicalValuation(
            at: query,
            in: "RUB",
            scopeID: "guest",
            timeContext: time,
            clock: FixedClock(now: dayStart.addingTimeInterval(2 * 86_400))
        )

        #expect(result.total == 900)
        #expect(result.resolutions.first?.opaqueAccountID == account.id.uuidString)
        #expect(result.resolutions.first?.kind == "exact")
        #expect(result.resolutions.first?.sourceID == "historical|tz=GMT")
        #expect(result.resolutions.first?.recordID?.hasPrefix("fx|USD->RUB|2024-01-01") == true)
        #expect(result.resolutions.first?.evidenceDayKey == "2024-01-01")
        #expect(result.resolutions.first?.observedAt == query)
        #expect(result.resolutions.first?.calendarPolicyID == "local-fx-exact-only-v1")
        #expect(result.key.inputRevision.evidence != 0)
    }
}
