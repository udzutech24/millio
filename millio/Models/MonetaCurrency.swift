//
//  MonetaCurrency.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Общий тип валюты для всех денежных сервисов (Финансы, Курсы, Кредиты и т.д.)
enum MonetaCurrency: String, Codable, CaseIterable, Identifiable {
    case RUB, USD, EUR, TRY, CNY
    
    var id: String { rawValue }
    
    var symbol: String {
        switch self {
        case .RUB: return "₽"
        case .USD: return "$"
        case .EUR: return "€"
        case .TRY: return "₺"
        case .CNY: return "¥"
        }
    }
    
    static var `default`: MonetaCurrency { .RUB }
}
