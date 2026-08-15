import Foundation
import SwiftData

/// Append-only кэш рыночных цен по дням (S9, AC10): единственный способ поставить синхронный
/// `MarketPriceProviding` внутрь `AccountBalanceEngine`/`AccountSnapshotRebuilder` (реплей не может
/// делать сетевой запрос сам — см. докстринг `AccountMarketPriceService`).
///
/// Live-апсерт разрешён только для сегодняшнего `dayKey`. Historical prefetch может добавить
/// отсутствующий provider close прошлого дня, но никогда не перезаписывает замороженную строку.
@Model
final class HistoricalAssetPrice: Persistable {
    var id: UUID = UUID()
    /// Символ тикера, ВСЕГДА в верхнем регистре (сравнение с `MarketMeta.symbol.uppercased()`).
    var symbol: String = ""
    var assetClassRaw: String = MarketAssetClass.stock.rawValue
    /// Календарный день цены, тот же формат "yyyy-MM-dd", что и `AccountEvent.dayKey`.
    var dayKey: String = ""
    var price: Decimal = 0
    /// Evidence source with frozen day-timezone metadata. Live observations use
    /// `market-backend|tz=<IANA>`; explicit historical providers use
    /// `historical:<provider>|tz=<IANA>`. Legacy rows without `tz` fail closed in valuation.
    var source: String = ""
    var fetchedAt: Date = Date()

    var assetClass: MarketAssetClass {
        get { MarketAssetClass(rawValue: assetClassRaw) ?? .stock }
        set { assetClassRaw = newValue.rawValue }
    }

    init(
        symbol: String,
        assetClass: MarketAssetClass,
        dayKey: String,
        price: Decimal,
        source: String,
        fetchedAt: Date = Date()
    ) {
        self.symbol = symbol.uppercased()
        self.assetClassRaw = assetClass.rawValue
        self.dayKey = dayKey
        self.price = price
        self.source = source
        self.fetchedAt = fetchedAt
    }

    // MARK: - Backup export/import
    //
    // В отличие от Account/AccountEvent/AccountGroup/AccountDailySnapshot, это НЕ часть event-sourcing
    // core reconciliation (нет выделенного merge-пути в ScopeMergeDedup) — участвует в общем
    // legacyData-экспорте reconciliation наравне с HistoricalRate (upsert по symbol+dayKey у импортёра).

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "HistoricalAssetPrice",
            "symbol": symbol,
            "assetClassRaw": assetClassRaw,
            "dayKey": dayKey,
            "price": "\(price)",
            "source": source,
            "fetchedAt": fetchedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        // Импорт выполняется через ModelContext в HistoricalAssetPriceImporter (AccountsCoreFeatureRegistration).
    }
}
