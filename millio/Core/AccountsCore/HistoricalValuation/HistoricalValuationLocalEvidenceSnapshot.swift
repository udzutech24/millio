import Foundation
import SwiftData

/// Immutable, Sendable evidence adapter over the existing local FX/market caches. SwiftData is
/// read exactly once on MainActor; resolver lookups then run on its own actor with no network and no
/// account×day fetch. Older rows are only candidates: calendar eligibility remains resolver-owned.
struct HistoricalValuationLocalEvidenceSnapshot: HistoricalValuationEvidenceProviding, Sendable {
    private struct FXRow: Sendable {
        let base: String
        let quote: String
        let value: Decimal
        let rateDate: Date
        let dayKey: String
        let source: String
        let fetchedAt: Date
        let recordID: String
    }

    private struct MarketRow: Sendable {
        let instrument: HistoricalMarketInstrument
        let value: Decimal
        let dayKey: String
        let source: String
        let fetchedAt: Date
        let recordID: String
    }

    private enum SnapshotError: Error {
        case fxFetchFailed
        case marketFetchFailed
    }

    private let fxRows: [FXRow]
    private let marketRows: [MarketRow]
    private let fxFetchFailed: Bool
    private let marketFetchFailed: Bool
    private let timeContext: HistoricalValuationTimeContext
    private let now: Date

    @MainActor
    static func make(
        modelContext: ModelContext,
        timeContext: HistoricalValuationTimeContext,
        now: Date
    ) -> Self {
        let rateRows: [HistoricalRate]
        let fxFetchFailed: Bool
        do {
            rateRows = try modelContext.fetch(FetchDescriptor<HistoricalRate>())
            fxFetchFailed = false
        } catch {
            rateRows = []
            fxFetchFailed = true
        }

        let priceRows: [HistoricalAssetPrice]
        let marketFetchFailed: Bool
        do {
            priceRows = try modelContext.fetch(FetchDescriptor<HistoricalAssetPrice>())
            marketFetchFailed = false
        } catch {
            priceRows = []
            marketFetchFailed = true
        }

        return Self(
            fxRows: rateRows.map { row in
                let base = row.baseCurrency.uppercased()
                let quote = row.quoteCurrency.uppercased()
                let dayKey = timeContext.dayKey(for: row.rateDate)
                return FXRow(
                    base: base,
                    quote: quote,
                    value: Decimal(row.rate),
                    rateDate: row.rateDate,
                    dayKey: dayKey,
                    source: row.source,
                    fetchedAt: row.fetchedAt,
                    recordID: Self.recordID(
                        kind: "fx", identity: "\(base)->\(quote)", dayKey: dayKey,
                        source: row.source, fetchedAt: row.fetchedAt
                    )
                )
            },
            marketRows: priceRows.map { row in
                let instrument = HistoricalMarketInstrument(symbol: row.symbol, assetClass: row.assetClass)
                return MarketRow(
                    instrument: instrument,
                    value: row.price,
                    dayKey: row.dayKey,
                    source: row.source,
                    fetchedAt: row.fetchedAt,
                    recordID: Self.recordID(
                        kind: "market", identity: "\(instrument.symbol):\(instrument.assetClass.rawValue)",
                        dayKey: row.dayKey, source: row.source, fetchedAt: row.fetchedAt
                    )
                )
            },
            fxFetchFailed: fxFetchFailed,
            marketFetchFailed: marketFetchFailed,
            timeContext: timeContext,
            now: now
        )
    }

    func fetchFXEvidence(
        for dependencies: Set<HistoricalFXDependencyKey>
    ) async throws -> [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] {
        guard !fxFetchFailed else { throw SnapshotError.fxFetchFailed }
        var result: [HistoricalFXDependencyKey: HistoricalValuationEvidenceBundle] = [:]
        for dependency in dependencies {
            var exact: [HistoricalValuationEvidenceRecord] = []
            var previous: [HistoricalValuationEvidenceRecord] = []

            for row in fxRows {
                guard row.source.lowercased().hasPrefix("historical"),
                      row.rateDate == timeContext.startOfDay(for: row.rateDate) else {
                    continue
                }
                let direct = row.base == dependency.pair.base && row.quote == dependency.pair.quote
                let inverse = row.base == dependency.pair.quote && row.quote == dependency.pair.base
                guard direct || inverse else { continue }
                let value = direct ? row.value : Decimal(1) / row.value
                let record = HistoricalValuationEvidenceRecord(
                    value: value,
                    dayKey: row.dayKey,
                    recordID: inverse ? "\(row.recordID)|inverse" : row.recordID,
                    sourceID: row.source.isEmpty ? "local-historical-rate" : row.source,
                    observedAt: row.fetchedAt
                )
                if row.dayKey < dependency.dayKey {
                    previous.append(record)
                } else if row.dayKey == dependency.dayKey {
                    // HistoricalRateStore persists provider historical values, including when D
                    // is still open. Finality remains provisional, but the evidence kind is exact.
                    exact.append(record)
                }
            }
            result[dependency] = .init(
                exact: exact,
                previousClose: previous,
                frozenClose: [],
                currentEstimate: []
            )
        }
        return result
    }

    func fetchMarketEvidence(
        for dependencies: Set<HistoricalMarketDependencyKey>
    ) async throws -> [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] {
        guard !marketFetchFailed else { throw SnapshotError.marketFetchFailed }
        var result: [HistoricalMarketDependencyKey: HistoricalValuationEvidenceBundle] = [:]
        for dependency in dependencies {
            var exact: [HistoricalValuationEvidenceRecord] = []
            var previous: [HistoricalValuationEvidenceRecord] = []
            var frozen: [HistoricalValuationEvidenceRecord] = []
            var current: [HistoricalValuationEvidenceRecord] = []

            for row in marketRows where row.instrument == dependency.instrument {
                let source = row.source.lowercased()
                let sourceTimeZone = Self.sourceTimeZoneID(row.source)
                let exactProviderRow = source.hasPrefix("historical:") && sourceTimeZone == timeContext.timeZoneID
                let currentCacheRow = source.hasPrefix("market-backend") && sourceTimeZone == timeContext.timeZoneID
                guard exactProviderRow || currentCacheRow else { continue }
                let record = HistoricalValuationEvidenceRecord(
                    value: row.value,
                    dayKey: row.dayKey,
                    recordID: row.recordID,
                    sourceID: row.source.isEmpty ? "local-historical-asset-price" : row.source,
                    observedAt: row.fetchedAt
                )
                if row.dayKey < dependency.dayKey, exactProviderRow {
                    previous.append(record)
                } else if row.dayKey == dependency.dayKey {
                    if exactProviderRow {
                        exact.append(record)
                    } else if dependency.dayKey == timeContext.dayKey(for: now), currentCacheRow {
                        current.append(record)
                    } else if currentCacheRow {
                        frozen.append(record)
                    }
                }
            }
            result[dependency] = .init(
                exact: exact,
                previousClose: previous,
                frozenClose: frozen,
                currentEstimate: current
            )
        }
        return result
    }

    private static func recordID(
        kind: String,
        identity: String,
        dayKey: String,
        source: String,
        fetchedAt: Date
    ) -> String {
        "\(kind)|\(identity)|\(dayKey)|\(source)|\(fetchedAt.timeIntervalSince1970)"
    }

    private static func sourceTimeZoneID(_ source: String) -> String? {
        source.split(separator: "|").first { $0.hasPrefix("tz=") }.map {
            String($0.dropFirst(3))
        }
    }
}
