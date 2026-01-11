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
    case exchangerateHost
    case frankfurter
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .erapi: return "(ER)"
        case .exchangerateHost: return "Exchangerate.host"
        case .frankfurter: return "Frankfurter"
        }
    }
    
    var subtitle: String {
        switch self {
        case .erapi: return "Много валют, высокая доступность"
        case .exchangerateHost: return "Широкая база"
        case .frankfurter: return "Официальные курсы Европейского ЦБ"
        }
    }
}
