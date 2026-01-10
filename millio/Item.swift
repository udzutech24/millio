//
//  Item.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData

@Model
final class Item: Persistable {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
    
    // MARK: - Exportable
    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "Item",
            "timestamp": timestamp.timeIntervalSince1970
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let timestampInterval = dict["timestamp"] as? TimeInterval else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
        // Это заглушка для демонстрации протокола
    }
}
