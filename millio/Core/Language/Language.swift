//
//  Language.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

enum Language: String, Codable, CaseIterable, Hashable {
    case system = "system"
    case english = "en"
    case russian = "ru"
    
    var displayName: String {
        switch self {
        case .system:
            return "Системный"
        case .english:
            return "English"
        case .russian:
            return "Русский"
        }
    }
    
    var locale: Locale? {
        switch self {
        case .system:
            return nil
        case .english:
            return Locale(identifier: "en")
        case .russian:
            return Locale(identifier: "ru")
        }
    }
}
