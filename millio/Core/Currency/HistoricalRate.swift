//
//  HistoricalRate.swift
//  millio
//
//  Created by Александр Сидоркин on 29.01.2026.
//

import Foundation
import SwiftData

/// Исторический курс валют на конкретную дату
@Model
final class HistoricalRate: Persistable {
    /// Базовая валюта (из)
    var baseCurrency: String = "USD"
    
    /// Котируемая валюта (в)
    var quoteCurrency: String = "RUB"
    
    /// Курс: сколько единиц quote за 1 единицу base
    var rate: Double = 1.0
    
    /// Дата курса (дневная гранулярность, начало дня в локальной TZ)
    var rateDate: Date = Date()
    
    /// Источник курса
    var source: String = ""
    
    /// Когда курс был получен
    var fetchedAt: Date = Date()
    
    init(
        baseCurrency: String,
        quoteCurrency: String,
        rate: Double,
        rateDate: Date,
        source: String,
        fetchedAt: Date = Date()
    ) {
        self.baseCurrency = baseCurrency.uppercased()
        self.quoteCurrency = quoteCurrency.uppercased()
        self.rate = rate
        self.rateDate = rateDate
        self.source = source
        self.fetchedAt = fetchedAt
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "HistoricalRate",
            "baseCurrency": baseCurrency,
            "quoteCurrency": quoteCurrency,
            "rate": rate,
            "rateDate": rateDate.timeIntervalSince1970,
            "source": source,
            "fetchedAt": fetchedAt.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "HistoricalRate"
    }
}
