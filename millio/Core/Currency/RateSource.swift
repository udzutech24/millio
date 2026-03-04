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
        case .erapi: return String(localized: "converter.rate_source.erapi.title")
        case .frankfurter: return String(localized: "converter.rate_source.frankfurter.title")
        }
    }
    
    var subtitle: String {
        switch self {
        case .erapi: return String(localized: "converter.rate_source.erapi.subtitle")
        case .frankfurter: return String(localized: "converter.rate_source.frankfurter.subtitle")
        }
    }
    
    var latestURL: URL? {
        switch self {
        case .erapi:
            return URL(string: "https://open.er-api.com/v6/latest/USD")
        case .frankfurter:
            return URL(string: "https://api.frankfurter.app/latest?from=USD")
        }
    }
}
