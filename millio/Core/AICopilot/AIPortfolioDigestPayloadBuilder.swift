//
//  AIPortfolioDigestPayloadBuilder.swift
//  millio
//

import Foundation

/// Цифры и тело запроса дайджеста портфеля. Чистая логика: SwiftData и сеть сюда не заходят.
enum AIPortfolioDigestPayloadBuilder {
    static let schemaVersion = "1"
    /// Пределы `PortfolioDigestRequestDto` — выход за них даёт 400.
    static let maxPositions = 64
    static let maxSymbolLength = 32
    static let maxCurrencyLength = 8

    struct PositionInput: Equatable {
        let accountID: UUID
        let name: String
        let symbol: String
        let assetClass: MarketAssetClass
        let quantity: Decimal
        /// Стоимость позиции — то же число, что в hero экрана позиции.
        let value: Decimal
        /// Цена единицы на начало окна; `nil` — позиции на начало окна ещё не было.
        let startUnitPrice: Decimal?
        /// Средняя цена открытых лотов («Куплено по» на экране позиции).
        let averageUnitCost: Decimal?
    }

    /// `portfolioTotal` — знаменатель «Доли в портфеле» экрана позиции: доли в дайджесте обязаны
    /// совпадать с экраном, поэтому делим на то же число, а не на сумму строк.
    static func figures(
        window: AIPortfolioWindow,
        currency: String,
        positions: [PositionInput],
        portfolioTotal: Decimal,
        excludedCurrencies: [String] = []
    ) -> AIPortfolioFigures? {
        let open = positions.filter { $0.value > 0 && $0.quantity > 0 }
        guard !open.isEmpty, portfolioTotal > 0 else { return nil }

        var changeAmount = Decimal.zero
        var startValue = Decimal.zero
        let rows = open.map { input -> AIPortfolioPositionFigures in
            // Позиция, открытая внутри окна, меряется от цены покупки: до неё движения у пользователя
            // не было, а ноль вместо изменения модель прочитала бы как «цена стоит на месте».
            let reference = input.startUnitPrice ?? input.averageUnitCost
            var changePercent = Decimal.zero
            if let reference, reference > 0 {
                let referenceValue = input.quantity * reference
                changeAmount += input.value - referenceValue
                startValue += referenceValue
                changePercent = (input.value / referenceValue - 1) * 100
            }
            return AIPortfolioPositionFigures(
                accountID: input.accountID,
                name: input.name,
                symbol: input.symbol,
                assetClass: input.assetClass,
                value: input.value,
                sharePercent: input.value / portfolioTotal * 100,
                changePercent: changePercent
            )
        }

        return AIPortfolioFigures(
            window: window,
            currency: currency,
            value: portfolioTotal,
            changeAmount: changeAmount,
            changePercent: startValue > 0 ? changeAmount / startValue * 100 : 0,
            positions: rows.sorted { $0.value != $1.value ? $0.value > $1.value : $0.symbol < $1.symbol },
            excludedCurrencies: excludedCurrencies
        )
    }

    static func makeRequest(figures: AIPortfolioFigures, locale: Locale) -> AIPortfolioDigestRequest {
        AIPortfolioDigestRequest(
            schemaVersion: schemaVersion,
            locale: AIPeriodSummaryPayloadBuilder.backendLocale(from: locale),
            currency: String(figures.currency.prefix(maxCurrencyLength)),
            window: figures.window.rawValue,
            totals: AIPortfolioDigestRequest.Totals(
                value: rounded(figures.value),
                changeAmount: rounded(figures.changeAmount),
                changePercent: rounded(figures.changePercent)
            ),
            // Позиции уже отсортированы по стоимости: при переполнении отрезаем самые мелкие.
            positions: figures.positions.prefix(maxPositions).map { position in
                AIPortfolioDigestRequest.Position(
                    symbol: String(position.symbol.prefix(maxSymbolLength)),
                    assetClass: position.assetClass.rawValue,
                    value: rounded(position.value),
                    sharePercent: rounded(position.sharePercent),
                    changePercent: rounded(position.changePercent)
                )
            }
        )
    }

    /// До сотых — те же числа, что экран показывает пользователю.
    /// Через строку, а не `NSDecimalNumber.doubleValue`: тот теряет последний бит (7.14 → 7.140000000000001),
    /// и в JSON для модели уехало бы «грязное» число, которого нет на экране.
    static func rounded(_ value: Decimal, scale: Int = 2) -> Double {
        var source = value
        var result = Decimal()
        NSDecimalRound(&result, &source, scale, .plain)
        return Double(result.description) ?? NSDecimalNumber(decimal: result).doubleValue
    }
}
