//
//  RateSource.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

extension Notification.Name {
    static let currencyRateSourceDidChange = Notification.Name("currencyRateSourceDidChange")
}

// MARK: - RateSourceCapability

struct RateSourceCapability {
    enum Scope {
        case globalFiatDaily
        case rubOfficialDaily
        case rubMarketDelayed
        case intradayPair
    }

    enum BaseCurrency {
        case usd
        case eur
        case rub
        case pairOnly
    }

    enum Freshness: String {
        case daily
        case hourly
        case delayed
        case realtime
    }

    enum LegalLabel: String {
        case official
        case reference
        case market
        case aggregator
    }

    let scope: Scope
    let baseCurrency: BaseCurrency
    let requiresAPIKey: Bool
    let supportsMatrixFetch: Bool
    let supportsHistorical: Bool
    let freshnessLabel: Freshness
    let legalLabel: LegalLabel
}

// MARK: - RateSource

/// Источник курсов валют
enum RateSource: String, CaseIterable, Identifiable {
    case millio
    case erapi
    case frankfurter
    case cbr

    var id: String { rawValue }

    var title: String {
        ConverterL10n.rateSourceTitle(self)
    }

    var subtitle: String {
        ConverterL10n.rateSourceSubtitle(self)
    }

    var latestURL: URL? {
        switch self {
        case .millio:
            return URL(string: "https://api.iqdrop.ru/api/v1/rates/latest")
        case .erapi:
            return URL(string: "https://open.er-api.com/v6/latest/USD")
        case .frankfurter:
            return URL(string: "https://api.frankfurter.app/latest?from=USD")
        case .cbr:
            return URL(string: "https://www.cbr.ru/scripts/XML_daily.asp")
        }
    }

    var capability: RateSourceCapability {
        switch self {
        case .millio:
            return RateSourceCapability(scope: .globalFiatDaily, baseCurrency: .usd,
                requiresAPIKey: false, supportsMatrixFetch: true, supportsHistorical: false,
                freshnessLabel: .daily, legalLabel: .aggregator)
        case .erapi:
            return RateSourceCapability(scope: .globalFiatDaily, baseCurrency: .usd,
                requiresAPIKey: false, supportsMatrixFetch: true, supportsHistorical: false,
                freshnessLabel: .daily, legalLabel: .reference)
        case .frankfurter:
            return RateSourceCapability(scope: .globalFiatDaily, baseCurrency: .eur,
                requiresAPIKey: false, supportsMatrixFetch: true, supportsHistorical: true,
                freshnessLabel: .daily, legalLabel: .reference)
        case .cbr:
            return RateSourceCapability(scope: .rubOfficialDaily, baseCurrency: .rub,
                requiresAPIKey: false, supportsMatrixFetch: true, supportsHistorical: true,
                freshnessLabel: .daily, legalLabel: .official)
        }
    }
}
