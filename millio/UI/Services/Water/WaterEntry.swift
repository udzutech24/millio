//
//  WaterEntry.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

/// Запись о выпитой воде
@Model
final class WaterEntry: Persistable {
    /// Количество воды в миллилитрах
    var amount: Int
    
    /// Дата и время записи
    var timestamp: Date
    
    init(amount: Int, timestamp: Date = Date()) {
        self.amount = amount
        self.timestamp = timestamp
    }
    
    // MARK: - Exportable
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "WaterEntry",
            "amount": amount,
            "timestamp": timestamp.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["amount"] as? Int != nil,
              dict["timestamp"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
}
