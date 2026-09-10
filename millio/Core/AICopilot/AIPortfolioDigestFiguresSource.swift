//
//  AIPortfolioDigestFiguresSource.swift
//  millio
//

import Foundation
import SwiftData

/// Цифры дайджеста из того же расчёта, что экран рыночной позиции (`MarketPortfolioValuation`).
@MainActor
struct AIPortfolioDigestFiguresSource {
    let modelContext: ModelContext
    let currency: String
    var now: () -> Date = Date.init
    var calendar: Calendar = .current

    func figures(for window: AIPortfolioWindow) -> AIPortfolioFigures? {
        let date = now()
        let valuation = MarketPortfolioValuation(modelContext: modelContext, now: date)
        let start = window.start(from: date, calendar: calendar)

        let inputs = valuation.peers(currency: currency).compactMap { account -> AIPortfolioDigestPayloadBuilder.PositionInput? in
            guard let meta = account.marketMeta, !meta.symbol.isEmpty else { return nil }
            return AIPortfolioDigestPayloadBuilder.PositionInput(
                accountID: account.id,
                name: account.name,
                symbol: meta.symbol.uppercased(),
                assetClass: meta.assetClass,
                quantity: valuation.quantity(of: account),
                value: valuation.positionValue(of: account),
                startUnitPrice: valuation.unitPrice(of: account, on: start),
                averageUnitCost: (try? StockLotEngine.replay(events: account.events ?? [], on: date))?.averageUnitCost
            )
        }

        return AIPortfolioDigestPayloadBuilder.figures(
            window: window,
            currency: currency,
            positions: inputs,
            portfolioTotal: valuation.portfolioTotal(currency: currency),
            excludedCurrencies: excludedCurrencies(valuation)
        )
    }

    /// Валюты открытых позиций, которые в дайджест не попали, — чтобы их отсутствие не выглядело потерей.
    private func excludedCurrencies(_ valuation: MarketPortfolioValuation) -> [String] {
        let others = valuation.activeMarketAccounts().filter {
            $0.currency != currency && valuation.positionValue(of: $0) > 0
        }
        return Array(Set(others.map(\.currency))).sorted()
    }
}
