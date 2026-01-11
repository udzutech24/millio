//
//  RateSource.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

/// Источник курсов валют
enum RateSource: String, CaseIterable, Identifiable {
    case erapi
    case frankfurter
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .erapi: return "(ER)"
        case .frankfurter: return "Frankfurter"
        }
    }
    
    var subtitle: String {
        switch self {
        case .erapi: return "Много валют, высокая доступность"
        case .frankfurter: return "Официальные курсы Европейского ЦБ"
        }
    }
}
