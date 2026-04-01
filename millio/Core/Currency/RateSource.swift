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
        ConverterL10n.rateSourceTitle(self)
    }
    
    var subtitle: String {
        ConverterL10n.rateSourceSubtitle(self)
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
