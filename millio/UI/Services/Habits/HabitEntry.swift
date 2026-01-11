//
//  HabitEntry.swift
//  millio
//
//  Created by Александр Сидоркин on 12.01.2026.
//

import Foundation
import SwiftData

/// Запись о сэкономленных единицах за день
@Model
final class HabitEntry: Persistable {
    /// Ссылка на привычку (через уникальный ID)
    var habitUniqueID: String = ""
    
    /// Дата записи
    var entryDate: Date = Date()
    
    /// Количество сэкономленных единиц (например, пачек сигарет, бутылок и т.д.)
    /// Если 0, значит просто отметка что не тратил в этот день
    var savedUnits: Double = 0.0
    
    /// Примечание (необязательно)
    var note: String?
    
    /// Дата создания записи
    var createdAt: Date = Date()
    
    init(
        habitUniqueID: String,
        entryDate: Date = Date(),
        savedUnits: Double = 0.0,
        note: String? = nil
    ) {
        self.habitUniqueID = habitUniqueID
        self.entryDate = entryDate
        self.savedUnits = savedUnits
        self.note = note
        self.createdAt = Date()
    }
    
    // MARK: - Exportable
    
    func export() throws -> Data {
        var dict: [String: Any] = [
            "type": "HabitEntry",
            "habitUniqueID": habitUniqueID,
            "entryDate": entryDate.timeIntervalSince1970,
            "savedUnits": savedUnits,
            "createdAt": createdAt.timeIntervalSince1970
        ]
        
        if let note = note {
            dict["note"] = note
        }
        
        return try JSONSerialization.data(withJSONObject: dict)
    }
    
    // MARK: - Importable
    
    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              dict["habitUniqueID"] as? String != nil,
              dict["entryDate"] as? TimeInterval != nil,
              dict["savedUnits"] as? Double != nil,
              dict["createdAt"] as? TimeInterval != nil else {
            throw AppError.backupCorrupted
        }
        // Импорт будет выполнен через ModelContext в DataRepository
    }
    
    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "HabitEntry" &&
        dict["habitUniqueID"] as? String != nil &&
        dict["entryDate"] as? TimeInterval != nil &&
        dict["savedUnits"] as? Double != nil
    }
}
