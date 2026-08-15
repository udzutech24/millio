import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Historical valuation local evidence snapshot")
struct HistoricalValuationLocalEvidenceSnapshotTests {
    @MainActor private static var retainedContainers: [ModelContainer] = []

    @MainActor
    private func context() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func date(_ dayKey: String, hour: Int = 0, timeZone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> Date {
        let parts = dayKey.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: .init(year: parts[0], month: parts[1], day: parts[2], hour: hour))!
    }

    @Test @MainActor
    func historicalFXRemainsExactOnOpenDay() async throws {
        let ctx = try context()
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day = "2026-01-13"
        ctx.insert(HistoricalRate(
            baseCurrency: "USD", quoteCurrency: "RUB", rate: 90,
            rateDate: date(day), source: "historical|tz=GMT", fetchedAt: date(day, hour: 12)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx, timeContext: time, now: date(day, hour: 18)
        )
        let key = HistoricalFXDependencyKey(dayKey: day, pair: .init(base: "USD", quote: "RUB"))

        let bundle = try await snapshot.fetchFXEvidence(for: [key])[key]

        #expect(bundle?.exact.count == 1)
        #expect(bundle?.currentEstimate.isEmpty == true)
        #expect(bundle?.frozenClose.isEmpty == true)
    }

    @Test @MainActor
    func rateDateFromAnotherTimezoneFailsClosed() async throws {
        let ctx = try context()
        let utc = TimeZone(secondsFromGMT: 0)!
        let istanbul = try #require(HistoricalValuationTimeContext(ianaTimeZoneID: "Europe/Istanbul"))
        let day = "2026-01-13"
        ctx.insert(HistoricalRate(
            baseCurrency: "USD", quoteCurrency: "RUB", rate: 90,
            rateDate: date(day, timeZone: utc), source: "historical|tz=GMT",
            fetchedAt: date(day, hour: 12, timeZone: utc)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx,
            timeContext: istanbul,
            now: date("2026-01-14", timeZone: utc)
        )
        let key = HistoricalFXDependencyKey(
            dayKey: istanbul.dayKey(for: date(day, hour: 12, timeZone: utc)),
            pair: .init(base: "USD", quote: "RUB")
        )

        let bundle = try await snapshot.fetchFXEvidence(for: [key])[key]

        #expect(bundle?.exact.isEmpty == true)
        #expect(bundle?.previousClose.isEmpty == true)
    }

    @Test @MainActor
    func timezoneBoundObservedMarketQuoteBecomesFrozenAfterDayCloses() async throws {
        let ctx = try context()
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day = "2026-01-13"
        ctx.insert(HistoricalAssetPrice(
            symbol: "AAPL", assetClass: .stock, dayKey: day, price: 150,
            source: "market-backend|tz=GMT", fetchedAt: date(day, hour: 18)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx, timeContext: time, now: date("2026-01-14")
        )
        let key = HistoricalMarketDependencyKey(
            dayKey: day,
            instrument: .init(symbol: "AAPL", assetClass: .stock)
        )

        let bundle = try await snapshot.fetchMarketEvidence(for: [key])[key]

        #expect(bundle?.exact.isEmpty == true)
        #expect(bundle?.frozenClose.first?.value == 150)
        #expect(bundle?.currentEstimate.isEmpty == true)
    }

    @Test @MainActor
    func timezoneBoundObservedMarketQuoteIsCurrentEstimateWhileDayIsOpen() async throws {
        let ctx = try context()
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day = "2026-01-13"
        ctx.insert(HistoricalAssetPrice(
            symbol: "AAPL", assetClass: .stock, dayKey: day, price: 150,
            source: "market-backend|tz=GMT", fetchedAt: date(day, hour: 12)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx, timeContext: time, now: date(day, hour: 18)
        )
        let key = HistoricalMarketDependencyKey(
            dayKey: day,
            instrument: .init(symbol: "AAPL", assetClass: .stock)
        )

        let bundle = try await snapshot.fetchMarketEvidence(for: [key])[key]

        #expect(bundle?.exact.isEmpty == true)
        #expect(bundle?.frozenClose.isEmpty == true)
        #expect(bundle?.currentEstimate.first?.value == 150)
    }

    @Test @MainActor
    func legacyMarketRowWithoutTimezoneEvidenceFailsClosed() async throws {
        let ctx = try context()
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day = "2026-01-13"
        ctx.insert(HistoricalAssetPrice(
            symbol: "AAPL", assetClass: .stock, dayKey: day, price: 150,
            source: "market-backend", fetchedAt: date(day, hour: 18)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx, timeContext: time, now: date("2026-01-14")
        )
        let key = HistoricalMarketDependencyKey(
            dayKey: day,
            instrument: .init(symbol: "AAPL", assetClass: .stock)
        )

        let bundle = try await snapshot.fetchMarketEvidence(for: [key])[key]

        #expect(bundle?.exact.isEmpty == true)
        #expect(bundle?.frozenClose.isEmpty == true)
        #expect(bundle?.currentEstimate.isEmpty == true)
    }

    @Test @MainActor
    func explicitTimezoneBoundHistoricalMarketRowCanBeExactEvidence() async throws {
        let ctx = try context()
        let time = HistoricalValuationTimeContext(timeZone: TimeZone(secondsFromGMT: 0)!)
        let day = "2026-01-13"
        ctx.insert(HistoricalAssetPrice(
            symbol: "AAPL", assetClass: .stock, dayKey: day, price: 150,
            source: "historical:test-provider|tz=GMT", fetchedAt: date(day, hour: 18)
        ))
        try ctx.save()
        let snapshot = HistoricalValuationLocalEvidenceSnapshot.make(
            modelContext: ctx, timeContext: time, now: date("2026-01-14")
        )
        let key = HistoricalMarketDependencyKey(
            dayKey: day,
            instrument: .init(symbol: "AAPL", assetClass: .stock)
        )

        let bundle = try await snapshot.fetchMarketEvidence(for: [key])[key]

        #expect(bundle?.exact.first?.value == 150)
        #expect(bundle?.currentEstimate.isEmpty == true)
    }
}
