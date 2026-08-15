import Foundation
import Testing
@testable import millio

@Suite("Historical valuation resolver")
struct HistoricalValuationResolverTests {
    private actor EvidenceProvider: HistoricalValuationEvidenceProviding {
        var fx: [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] = [:]
        var market: [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] = [:]
        private(set) var fxCalls: [Set<HistoricalFXDependencyKey>] = []
        private(set) var marketCalls: [Set<HistoricalMarketDependencyKey>] = []

        func setFX(_ values: [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle]) {
            fx = values
        }

        func setMarket(_ values: [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle]) {
            market = values
        }

        func fetchFXEvidence(
            for dependencies: Set<HistoricalFXDependencyKey>
        ) async throws -> [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] {
            fxCalls.append(dependencies)
            return fx.filter { dependencies.contains($0.key) }
        }

        func fetchMarketEvidence(
            for dependencies: Set<HistoricalMarketDependencyKey>
        ) async throws -> [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] {
            marketCalls.append(dependencies)
            return market.filter { dependencies.contains($0.key) }
        }

        func calls() -> (fx: [Set<HistoricalFXDependencyKey>], market: [Set<HistoricalMarketDependencyKey>]) {
            (fxCalls, marketCalls)
        }
    }

    private struct ThrowingEvidenceProvider: HistoricalValuationEvidenceProviding {
        enum Failure: Error { case expected }

        func fetchFXEvidence(
            for dependencies: Set<HistoricalFXDependencyKey>
        ) async throws -> [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] {
            throw Failure.expected
        }

        func fetchMarketEvidence(
            for dependencies: Set<HistoricalMarketDependencyKey>
        ) async throws -> [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] {
            throw Failure.expected
        }
    }

    private let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
    private let fiat = HistoricalValuationCalendarPolicy.fiat(id: "fiat-v1")
    private let exchange = HistoricalValuationCalendarPolicy.exchange(id: "exchange-v1")
    private let crypto = HistoricalValuationCalendarPolicy.crypto24x7(id: "crypto-v1")

    private func date(_ dayKey: String, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: hour
        ))!
    }

    private func evidence(
        _ value: Decimal,
        dayKey: String,
        id: String,
        observedHour: Int = 12
    ) -> HistoricalValuationEvidenceRecord {
        HistoricalValuationEvidenceRecord(
            value: value,
            dayKey: dayKey,
            recordID: id,
            sourceID: "test-provider",
            observedAt: date(dayKey, hour: observedHour)
        )
    }

    private func native(
        id: String,
        origin: HistoricalValuationContributionOrigin = .core,
        value: Decimal = 10,
        currency: String = "USD",
        dayKey: String = "2026-01-13"
    ) -> HistoricalValuationContributionRequest {
        .init(
            id: id,
            origin: origin,
            valuationDate: date(dayKey),
            input: .native(value: value, currency: currency, fxPolicy: fiat)
        )
    }

    private func resolution(
        _ id: String,
        in results: [HistoricalValuationContributionResolution]
    ) -> HistoricalValuationContributionResolution? {
        results.first { $0.requestID == id }
    }

    @Test
    func nativeParityAndProvenZeroNeverFetchEvidence() async {
        let provider = EvidenceProvider()
        let requests = [
            native(id: "parity", value: 12, currency: "RUB"),
            native(id: "zero", value: 0, currency: "USD")
        ]

        let result = await HistoricalValuationResolver().resolve(
            requests: requests,
            displayCurrency: "RUB",
            timeContext: time,
            now: date("2026-01-14"),
            evidenceProvider: provider
        )
        let calls = await provider.calls()

        #expect(resolution("parity", in: result)?.value == 12)
        #expect(resolution("parity", in: result)?.dependencies.map(\.kind) == [.nativeParity])
        #expect(resolution("zero", in: result)?.value == 0)
        #expect(resolution("zero", in: result)?.dependencies.isEmpty == true)
        #expect(calls.fx.isEmpty)
        #expect(calls.market.isEmpty)
    }

    @Test
    func currencyValidationAcceptsCanonicalISOAndRejectsBlankAndUnknownCodes() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let usdKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        await provider.setFX([
            usdKey: .init(exact: [evidence(90, dayKey: day, id: "usd-rub")])
        ])

        let results = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "blank", currency: " ", dayKey: day),
                native(id: "unknown", currency: "ZZZ", dayKey: day),
                native(id: "valid", currency: " usd ", dayKey: day)
            ],
            displayCurrency: "rub",
            timeContext: time,
            now: date("2026-01-14"),
            evidenceProvider: provider
        )
        let calls = await provider.calls()

        #expect(resolution("blank", in: results)?.dependencies.first?.reasonCode == "invalid_account_currency")
        #expect(resolution("unknown", in: results)?.dependencies.first?.reasonCode == "invalid_account_currency")
        #expect(resolution("valid", in: results)?.value == 900)
        #expect(calls.fx == [[usdKey]])
    }

    @Test
    func exactPreviousFrozenAndOpenCurrentReturnTypedProvenance() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let exactKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let weekendKey = HistoricalFXDependencyKey(dayKey: "2026-01-10", pair: .init(base: "EUR", quote: "RUB"))
        let frozenKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "CNY", quote: "RUB"))
        let currentKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "TRY", quote: "RUB"))
        await provider.setFX([
            exactKey: .init(exact: [evidence(90, dayKey: day, id: "fx-exact")]),
            weekendKey: .init(previousClose: [evidence(100, dayKey: "2026-01-09", id: "fx-prev")]),
            frozenKey: .init(frozenClose: [evidence(11, dayKey: day, id: "fx-frozen", observedHour: 22)]),
            currentKey: .init(currentEstimate: [evidence(2.5, dayKey: day, id: "fx-current")])
        ])

        let closed = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "exact", currency: "USD", dayKey: day),
                native(id: "previous", currency: "EUR", dayKey: "2026-01-10"),
                native(id: "frozen", currency: "CNY", dayKey: day)
            ],
            displayCurrency: "RUB",
            timeContext: time,
            now: date("2026-01-14"),
            evidenceProvider: provider
        )
        let open = await HistoricalValuationResolver().resolve(
            requests: [native(id: "current", currency: "TRY", dayKey: day)],
            displayCurrency: "RUB",
            timeContext: time,
            now: date(day, hour: 18),
            evidenceProvider: provider
        )

        #expect(resolution("exact", in: closed)?.dependencies.first?.kind == .exact)
        #expect(resolution("exact", in: closed)?.dependencies.first?.provenance?.recordID == "fx-exact")
        #expect(resolution("previous", in: closed)?.dependencies.first?.kind == .previousClose)
        #expect(resolution("previous", in: closed)?.dependencies.first?.provenance?.calendarPolicyID == "fiat-v1")
        #expect(resolution("frozen", in: closed)?.dependencies.first?.kind == .frozenClose)
        #expect(resolution("current", in: open)?.dependencies.first?.kind == .currentEstimate)
        #expect(resolution("current", in: open)?.quality == .estimated)
    }

    @Test
    func currentQuoteCannotEnterAClosedDayAndWeekdayMissCannotUseStalePreviousClose() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let currentKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let staleKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "EUR", quote: "RUB"))
        await provider.setFX([
            currentKey: .init(currentEstimate: [evidence(90, dayKey: day, id: "current")]),
            staleKey: .init(previousClose: [evidence(100, dayKey: "2026-01-12", id: "previous")])
        ])

        let result = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "closed-current", currency: "USD", dayKey: day),
                native(id: "weekday-miss", currency: "EUR", dayKey: day)
            ],
            displayCurrency: "RUB",
            timeContext: time,
            now: date("2026-01-14"),
            evidenceProvider: provider
        )

        #expect(resolution("closed-current", in: result)?.value == nil)
        #expect(resolution("closed-current", in: result)?.dependencies.first?.kind == .unavailable)
        #expect(resolution("closed-current", in: result)?.dependencies.first?.reasonCode == "current_estimate_closed_day")
        #expect(resolution("weekday-miss", in: result)?.value == nil)
        #expect(resolution("weekday-miss", in: result)?.dependencies.first?.reasonCode == "previous_close_ineligible")
    }

    @Test
    func mislabeledStaleAndFutureCurrentQuotesFailClosed() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let staleKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let futureKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "EUR", quote: "RUB"))
        let stale = HistoricalValuationEvidenceRecord(
            value: 90,
            dayKey: day,
            recordID: "stale",
            sourceID: "test-provider",
            observedAt: date("2026-01-12", hour: 23)
        )
        let future = evidence(100, dayKey: day, id: "future", observedHour: 23)
        await provider.setFX([
            staleKey: .init(currentEstimate: [stale]),
            futureKey: .init(currentEstimate: [future])
        ])

        let results = await HistoricalValuationResolver().resolve(
            requests: [native(id: "stale", currency: "USD"), native(id: "future", currency: "EUR")],
            displayCurrency: "RUB", timeContext: time,
            now: date(day, hour: 18), evidenceProvider: provider
        )

        #expect(results.allSatisfy { $0.value == nil })
        #expect(results.allSatisfy { $0.dependencies.first?.reasonCode == "invalid_current_estimate_day" })
    }

    @Test
    func priceTimesFXRequiresBothDimensionsAcrossTheFullCrossMatrix() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let instrument = HistoricalMarketInstrument(symbol: "AAPL", assetClass: .stock)
        let marketKey = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        let fxKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))

        for (hasPrice, hasFX) in [(true, true), (true, false), (false, true), (false, false)] {
            await provider.setMarket(hasPrice ? [
                marketKey: .init(exact: [evidence(150, dayKey: day, id: "price")])
            ] : [:])
            await provider.setFX(hasFX ? [
                fxKey: .init(exact: [evidence(90, dayKey: day, id: "fx")])
            ] : [:])
            let request = HistoricalValuationContributionRequest(
                id: "market",
                origin: .core,
                valuationDate: date(day),
                input: .market(
                    quantity: 2,
                    instrument: instrument,
                    quoteCurrency: "USD",
                    pricePolicy: exchange,
                    fxPolicy: fiat
                )
            )

            let results = await HistoricalValuationResolver().resolve(
                requests: [request],
                displayCurrency: "RUB",
                timeContext: time,
                now: date("2026-01-14"),
                evidenceProvider: provider
            )
            let result = results.first

            #expect(result?.value == (hasPrice && hasFX ? 27_000 : nil))
            #expect(result?.unresolvedDimensions.contains(.marketPrice) == !hasPrice)
            #expect(result?.unresolvedDimensions.contains(.fxRate) == !hasFX)
        }
    }

    @Test
    func sameCurrencyMarketNeedsPriceButDoesNotFetchFX() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let instrument = HistoricalMarketInstrument(symbol: "SBER", assetClass: .stock)
        let marketKey = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        await provider.setMarket([
            marketKey: .init(exact: [evidence(300, dayKey: day, id: "price")])
        ])
        let request = HistoricalValuationContributionRequest(
            id: "market",
            origin: .compatibility,
            valuationDate: date(day),
            input: .market(
                quantity: 3,
                instrument: instrument,
                quoteCurrency: "RUB",
                pricePolicy: exchange,
                fxPolicy: fiat
            )
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [request], displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )
        let result = results.first
        let calls = await provider.calls()

        #expect(result?.value == 900)
        #expect(result?.dependencies.map(\.kind) == [.exact, .nativeParity])
        #expect(calls.fx.isEmpty)
        #expect(calls.market.count == 1)
    }

    @Test
    func crypto24x7MissIsUnavailableEvenWhenAnOlderRecordExists() async {
        let provider = EvidenceProvider()
        let day = "2026-01-10"
        let instrument = HistoricalMarketInstrument(symbol: "BTC", assetClass: .crypto)
        let key = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        await provider.setMarket([
            key: .init(previousClose: [evidence(90_000, dayKey: "2026-01-09", id: "old")])
        ])
        let request = HistoricalValuationContributionRequest(
            id: "crypto", origin: .core, valuationDate: date(day),
            input: .market(
                quantity: 1, instrument: instrument, quoteCurrency: "USD",
                pricePolicy: crypto, fxPolicy: fiat
            )
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [request], displayCurrency: "USD", timeContext: time,
            now: date("2026-01-11"), evidenceProvider: provider
        )
        let result = results.first

        #expect(result?.value == nil)
        #expect(result?.unresolvedDimensions == [.marketPrice])
        #expect(result?.dependencies.first?.reasonCode == "previous_close_ineligible")
    }

    @Test
    func invalidAndZeroEvidenceAreUnavailableInsteadOfFallingThrough() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let zero = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let nan = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "EUR", quote: "RUB"))
        await provider.setFX([
            zero: .init(exact: [evidence(0, dayKey: day, id: "zero")]),
            nan: .init(exact: [evidence(.nan, dayKey: day, id: "nan")])
        ])

        let result = await HistoricalValuationResolver().resolve(
            requests: [native(id: "zero", currency: "USD"), native(id: "nan", currency: "EUR")],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )

        #expect(resolution("zero", in: result)?.dependencies.first?.reasonCode == "invalid_exact_value")
        #expect(resolution("nan", in: result)?.dependencies.first?.reasonCode == "invalid_exact_value")
    }

    @Test
    func multiplicationOverflowIsANativeValuationFailureForNativeAndMarketInputs() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let fxKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let instrument = HistoricalMarketInstrument(symbol: "SBER", assetClass: .stock)
        let marketKey = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        await provider.setFX([
            fxKey: .init(exact: [evidence(2, dayKey: day, id: "fx")])
        ])
        await provider.setMarket([
            marketKey: .init(exact: [evidence(2, dayKey: day, id: "price")])
        ])
        let market = HistoricalValuationContributionRequest(
            id: "market-overflow", origin: .core, valuationDate: date(day),
            input: .market(
                quantity: .greatestFiniteMagnitude,
                instrument: instrument,
                quoteCurrency: "RUB",
                pricePolicy: exchange,
                fxPolicy: fiat
            )
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "native-overflow", value: .greatestFiniteMagnitude),
                market
            ],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )

        for id in ["native-overflow", "market-overflow"] {
            let result = resolution(id, in: results)
            #expect(result?.value == nil)
            #expect(result?.unresolvedDimensions == [.nativeBalance])
            #expect(result?.dependencies.last?.reasonCode == "valuation_overflow")
        }
    }

    @Test
    func duplicateOpaqueIDsPreserveEveryRequestAndInputOrder() async {
        let provider = EvidenceProvider()
        let requests = [
            native(id: "shared", origin: .core, value: 10, currency: "RUB"),
            native(id: "shared", origin: .compatibility, value: 20, currency: "RUB")
        ]

        let results = await HistoricalValuationResolver().resolve(
            requests: requests,
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )

        #expect(results.count == requests.count)
        #expect(results.map(\.requestID) == ["shared", "shared"])
        #expect(results.map(\.origin) == [.core, .compatibility])
        #expect(results.map(\.value) == [10, 20])
    }

    @Test
    func conflictingCalendarPoliciesFailClosedForEveryAffectedRequestWithoutFetching() async {
        let provider = EvidenceProvider()
        let first = HistoricalValuationContributionRequest(
            id: "core", origin: .core, valuationDate: date("2026-01-13"),
            input: .native(value: 10, currency: "USD", fxPolicy: .fiat(id: "provider-a-v1"))
        )
        let second = HistoricalValuationContributionRequest(
            id: "compat", origin: .compatibility, valuationDate: date("2026-01-13"),
            input: .native(value: 20, currency: "USD", fxPolicy: .fiat(id: "provider-b-v1"))
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [first, second],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )
        let calls = await provider.calls()

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.value == nil })
        #expect(results.allSatisfy { $0.dependencies.first?.reasonCode == "conflicting_calendar_policy" })
        #expect(calls.fx.isEmpty)
    }

    @Test
    func allResolutionKindsHaveIdenticalCoreAndCompatibilitySemantics() async {
        let provider = EvidenceProvider()
        let exactDay = "2026-01-12"
        let weekendDay = "2026-01-10"
        let openDay = "2026-01-13"
        let keys: [String: HistoricalFXDependencyKey] = [
            "exact": .init(dayKey: exactDay, pair: .init(base: "USD", quote: "RUB")),
            "previousClose": .init(dayKey: weekendDay, pair: .init(base: "EUR", quote: "RUB")),
            "frozenClose": .init(dayKey: exactDay, pair: .init(base: "CNY", quote: "RUB")),
            "currentEstimate": .init(dayKey: openDay, pair: .init(base: "TRY", quote: "RUB"))
        ]
        await provider.setFX([
            keys["exact"]!: .init(exact: [evidence(90, dayKey: exactDay, id: "exact")]),
            keys["previousClose"]!: .init(previousClose: [evidence(100, dayKey: "2026-01-09", id: "previous")]),
            keys["frozenClose"]!: .init(frozenClose: [evidence(11, dayKey: exactDay, id: "frozen")]),
            keys["currentEstimate"]!: .init(currentEstimate: [evidence(2.5, dayKey: openDay, id: "current")])
        ])
        let cases: [(String, String, String)] = [
            ("nativeParity", "RUB", exactDay),
            ("exact", "USD", exactDay),
            ("previousClose", "EUR", weekendDay),
            ("frozenClose", "CNY", exactDay),
            ("currentEstimate", "TRY", openDay),
            ("unavailable", "GBP", exactDay)
        ]
        let requests = HistoricalValuationContributionOrigin.allCases.flatMap { origin in
            cases.map { kind, currency, dayKey in
                native(id: "\(origin.rawValue)-\(kind)", origin: origin, currency: currency, dayKey: dayKey)
            }
        }

        let results = await HistoricalValuationResolver().resolve(
            requests: requests,
            displayCurrency: "RUB", timeContext: time,
            now: date(openDay, hour: 18), evidenceProvider: provider
        )

        for (kind, _, _) in cases {
            let core = resolution("core-\(kind)", in: results)
            let compatibility = resolution("compatibility-\(kind)", in: results)
            #expect(core?.dependencies.first?.kind == HistoricalValuationResolutionKind(rawValue: kind))
            #expect(core?.dependencies == compatibility?.dependencies)
            #expect(core?.value == compatibility?.value)
        }
    }

    @Test
    func providerFailuresStayTypedForBothDimensions() async {
        let day = "2026-01-13"
        let instrument = HistoricalMarketInstrument(symbol: "AAPL", assetClass: .stock)
        let market = HistoricalValuationContributionRequest(
            id: "market", origin: .core, valuationDate: date(day),
            input: .market(
                quantity: 2, instrument: instrument, quoteCurrency: "USD",
                pricePolicy: exchange, fxPolicy: fiat
            )
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [native(id: "native"), market],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: ThrowingEvidenceProvider()
        )

        #expect(resolution("native", in: results)?.dependencies.first?.reasonCode == "fx_evidence_fetch_failed")
        #expect(resolution("market", in: results)?.unresolvedDimensions == [.marketPrice, .fxRate])
        #expect(resolution("market", in: results)?.dependencies.map(\.reasonCode) == [
            "market_evidence_fetch_failed", "fx_evidence_fetch_failed"
        ])
    }

    @Test
    func negativeNativeAndMarketContributionsPreserveTheirSign() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let fxKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let instrument = HistoricalMarketInstrument(symbol: "AAPL", assetClass: .stock)
        let marketKey = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        await provider.setFX([fxKey: .init(exact: [evidence(90, dayKey: day, id: "fx")])])
        await provider.setMarket([marketKey: .init(exact: [evidence(150, dayKey: day, id: "price")])])
        let market = HistoricalValuationContributionRequest(
            id: "market", origin: .core, valuationDate: date(day),
            input: .market(
                quantity: -2, instrument: instrument, quoteCurrency: "RUB",
                pricePolicy: exchange, fxPolicy: fiat
            )
        )

        let results = await HistoricalValuationResolver().resolve(
            requests: [native(id: "native", value: -10), market],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )

        #expect(resolution("native", in: results)?.value == -900)
        #expect(resolution("market", in: results)?.value == -300)
    }

    @Test
    func coexistingEvidenceUsesTheNormativePrecedenceOrder() async {
        let provider = EvidenceProvider()
        let weekend = "2026-01-10"
        let exactKey = HistoricalFXDependencyKey(dayKey: weekend, pair: .init(base: "USD", quote: "RUB"))
        let previousKey = HistoricalFXDependencyKey(dayKey: weekend, pair: .init(base: "EUR", quote: "RUB"))
        let frozenKey = HistoricalFXDependencyKey(dayKey: "2026-01-12", pair: .init(base: "CNY", quote: "RUB"))
        await provider.setFX([
            exactKey: .init(
                exact: [evidence(90, dayKey: weekend, id: "exact")],
                previousClose: [evidence(80, dayKey: "2026-01-09", id: "previous")],
                frozenClose: [evidence(85, dayKey: weekend, id: "frozen")],
                currentEstimate: [evidence(95, dayKey: weekend, id: "current")]
            ),
            previousKey: .init(
                previousClose: [evidence(100, dayKey: "2026-01-09", id: "previous")],
                frozenClose: [evidence(105, dayKey: weekend, id: "frozen")]
            ),
            frozenKey: .init(
                previousClose: [evidence(10, dayKey: "2026-01-09", id: "ineligible")],
                frozenClose: [evidence(11, dayKey: "2026-01-12", id: "frozen")]
            )
        ])

        let results = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "exact", currency: "USD", dayKey: weekend),
                native(id: "previous", currency: "EUR", dayKey: weekend),
                native(id: "frozen", currency: "CNY", dayKey: "2026-01-12")
            ],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )

        #expect(resolution("exact", in: results)?.dependencies.first?.kind == .exact)
        #expect(resolution("previous", in: results)?.dependencies.first?.kind == .previousClose)
        #expect(resolution("frozen", in: results)?.dependencies.first?.kind == .frozenClose)
    }

    @Test
    func sharedCoreAndCompatibilityDependenciesAreFetchedOnceAndResolveIdentically() async {
        let provider = EvidenceProvider()
        let day = "2026-01-13"
        let fxKey = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))
        let instrument = HistoricalMarketInstrument(symbol: "AAPL", assetClass: .stock)
        let marketKey = HistoricalMarketDependencyKey(dayKey: day, instrument: instrument)
        await provider.setFX([
            fxKey: .init(exact: [evidence(90, dayKey: day, id: "fx")])
        ])
        await provider.setMarket([
            marketKey: .init(exact: [evidence(150, dayKey: day, id: "price")])
        ])

        let coreMarket = HistoricalValuationContributionRequest(
            id: "core-market", origin: .core, valuationDate: date(day),
            input: .market(
                quantity: 2, instrument: instrument, quoteCurrency: "USD",
                pricePolicy: exchange, fxPolicy: fiat
            )
        )
        let legacyMarket = HistoricalValuationContributionRequest(
            id: "legacy-market", origin: .compatibility, valuationDate: date(day),
            input: .market(
                quantity: 2, instrument: instrument, quoteCurrency: "USD",
                pricePolicy: exchange, fxPolicy: fiat
            )
        )

        let result = await HistoricalValuationResolver().resolve(
            requests: [
                native(id: "core", origin: .core),
                native(id: "legacy", origin: .compatibility),
                coreMarket,
                legacyMarket
            ],
            displayCurrency: "RUB", timeContext: time,
            now: date("2026-01-14"), evidenceProvider: provider
        )
        let calls = await provider.calls()

        #expect(resolution("core", in: result)?.value == resolution("legacy", in: result)?.value)
        #expect(resolution("core", in: result)?.dependencies == resolution("legacy", in: result)?.dependencies)
        #expect(resolution("core-market", in: result)?.value == resolution("legacy-market", in: result)?.value)
        #expect(resolution("core-market", in: result)?.dependencies == resolution("legacy-market", in: result)?.dependencies)
        #expect(calls.fx.count == 1)
        #expect(calls.fx.first?.count == 1)
        #expect(calls.market.count == 1)
        #expect(calls.market.first?.count == 1)
    }
}
