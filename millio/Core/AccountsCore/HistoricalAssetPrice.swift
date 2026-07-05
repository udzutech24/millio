import Foundation
import SwiftData

/// Append-only кэш рыночных цен по дням (S9, AC10): единственный способ поставить синхронный
/// `MarketPriceProviding` внутрь `AccountBalanceEngine`/`AccountSnapshotRebuilder` (реплей не может
/// делать сетевой запрос сам — см. докстринг `AccountMarketPriceService`).
///
/// Апсерт разрешён ТОЛЬКО для СЕГОДНЯШНЕГО `dayKey` (см. `AccountMarketPriceService.upsertTodayPrice`) —
/// прошлые дни, однажды записанные, больше не перезаписываются. Со временем (при регулярном онлайн-
/// использовании приложения) таблица органически накапливает реальную историю закрытий БЕЗ единого
/// платного бэкфилла (S9: не жечь квоту котировок на историю).
@Model
final class HistoricalAssetPrice: Persistable {
    var id: UUID = UUID()
    /// Символ тикера, ВСЕГДА в верхнем регистре (сравнение с `MarketMeta.symbol.uppercased()`).
    var symbol: String = ""
    var assetClassRaw: String = MarketAssetClass.stock.rawValue
    /// Календарный день цены, тот же формат "yyyy-MM-dd", что и `AccountEvent.dayKey`.
    var dayKey: String = ""
    var price: Decimal = 0
    /// Источник цены (для диагностики) — сейчас всегда "market-backend" (тот же клиент, что питает старый мир).
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
