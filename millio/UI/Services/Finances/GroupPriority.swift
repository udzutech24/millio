//
//  GroupPriority.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import Foundation

/// Приоритет группы
enum GroupPriority: String, Codable, CaseIterable {
    case low = "low" // Низкий
    case normal = "normal" // Обычный
    case high = "high" // Высокий
    
    var displayName: String {
        switch self {
        case .low: return "Низкий"
        case .normal: return "Обычный"
        case .high: return "Высокий"
        }
    }
    
    /// Порядок сортировки (меньше = выше в списке)
    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .normal: return 1
        case .low: return 2
        }
    }
}
