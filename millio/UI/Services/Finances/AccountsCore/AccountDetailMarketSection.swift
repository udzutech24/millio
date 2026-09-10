import SwiftUI
import SwiftData

/// Рыночный счёт (`.marketInvestment`): количество, цены, P/L и витрина hero-графика.
extension AccountDetailView {
    // MARK: - Рыночный счёт (.marketInvestment) — qty/цена/P&L (Фаза 4)

    /// UI consumes the pure FIFO replay; it must not grow a second quantity/cost-basis engine.
    var stockSnapshot: StockPositionSnapshot? {
        _ = refreshToken
        return try? StockLotEngine.replay(events: account.events ?? [], on: Date())
    }

    var currentQuantity: Decimal {
        stockSnapshot?.quantity ?? 0
    }

    var todayQuote: HistoricalAssetPrice? {
        guard let symbol = account.marketMeta?.symbol.uppercased() else { return nil }
        let dayKey = AccountEvent.dayKey(for: Date())
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate { $0.symbol == symbol && $0.dayKey == dayKey }
        )
        return try? modelContext.fetch(descriptor).first
    }

    var latestCachedQuote: HistoricalAssetPrice? {
        guard let symbol = account.marketMeta?.symbol.uppercased() else { return nil }
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate { $0.symbol == symbol },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        return try? modelContext.fetch(descriptor).first
    }

    /// Unrealized P&L excludes realized proceeds and is based only on remaining FIFO lots.
    var unrealizedPL: Decimal {
        stockSnapshot?.unrealizedProfitLoss(at: currentUnitPrice) ?? 0
    }

    var stockTotalReturn: Decimal {
        stockSnapshot?.totalReturn(at: currentUnitPrice) ?? 0
    }

    /// Текущая цена за единицу + признак «не сегодняшняя» (пометка «посл. известная»). `nil` цены из
    /// live-кэша (`AccountMarketPriceService`) трактуем как «нет сегодняшних данных» — падаем на
    /// последнюю цену buy/sell/revaluation из событий (офлайн/auth-error, брифинг Фазы 4, задача 2).
    var currentUnitPrice: Decimal {
        if let todayQuote { return todayQuote.price }
        if let latestCachedQuote { return latestCachedQuote.price }
        return (account.events ?? [])
            .sorted { $0.date < $1.date }
            .last(where: { ($0.type == .buy || $0.type == .sell) && $0.unitPrice != nil })?
            .unitPrice ?? 0
    }

    /// `true`, если сегодняшней живой цены в кэше нет вовсе — карточка показывает пометку
    /// «посл. известная цена» (упрощение, задокументировано: не различаем «вчера»/«неделю назад»).
    var isPriceStale: Bool {
        todayQuote == nil
    }

    /// Данные hero-карточки рыночной позиции (единая карточка вместо hero + плашка «ПОЗИЦИЯ» +
    /// таблица на 8 строк). `nil`, если реплей событий упал — тогда hero молча падает на
    /// стандартную начинку счёта вместо падения экрана целиком (см. `AccountDetailView.body`).
    var investmentPresentation: InvestmentHeroPresentation? {
        guard account.kind == .marketInvestment, let snapshot = stockSnapshot else { return nil }
        _ = refreshToken
        let invested = snapshot.openCostBasis
        // Знаменатель доходности — себестоимость ОТКРЫТОЙ позиции, а не сумма всех покупок за
        // историю: снапшот не хранит второе число, а плодить его ради процента не стоит (KISS).
        let returnPercent: Decimal? = invested > 0 ? (stockTotalReturn / invested) * 100 : nil
        return InvestmentHeroPresentation(
            currency: account.currency,
            currencySymbol: MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency,
            positionValue: balanceToday,
            totalReturn: stockTotalReturn,
            returnPercent: returnPercent,
            quantity: snapshot.quantity,
            currentUnitPrice: currentUnitPrice,
            averageUnitCost: snapshot.averageUnitCost,
            invested: invested,
            dividends: snapshot.dividends,
            realizedProfitLoss: snapshot.realizedProfitLoss,
            fees: snapshot.totalFees,
            portfolioSharePercent: portfolioSharePercent,
            sparkline: priceHistoryPoints,
            sparklineMonths: sparklineMonths,
            latestPriceAsOf: latestPriceAsOf
        )
    }

    /// Реальные точки цены символа из append-only кэша `HistoricalAssetPrice` — ничего не
    /// синтезируем. Меньше 2 точек (нет истории или только сегодняшняя live-цена) — график не
    /// строим вовсе, а не рисуем плоскую линию из одной точки.
    var priceHistoryPoints: [InvestmentPricePoint] {
        guard let symbol = account.marketMeta?.symbol, !symbol.isEmpty else { return [] }
        let upper = symbol.uppercased()
        let descriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper },
            sortBy: [SortDescriptor(\.dayKey, order: .forward)]
        )
        guard let rows = try? modelContext.fetch(descriptor), rows.count >= 2 else { return [] }
        // ~6 месяцев — дальше линия на sparkline-высоте карточки становится нечитаемой.
        return rows.suffix(183).compactMap { row in
            guard let date = Self.dayKeyFormatter.date(from: row.dayKey) else { return nil }
            return InvestmentPricePoint(date: date, price: NSDecimalNumber(decimal: row.price).doubleValue)
        }
    }

    var sparklineMonths: Int {
        guard let first = priceHistoryPoints.first?.date, let last = priceHistoryPoints.last?.date else { return 0 }
        let months = Calendar.current.dateComponents([.month], from: first, to: last).month ?? 0
        return max(months, 1)
    }

    var latestPriceAsOf: Date? {
        guard !priceHistoryPoints.isEmpty else { return nil }
        return todayQuote?.fetchedAt ?? latestCachedQuote?.fetchedAt
    }

    static let dayKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    /// Доля позиции в общей стоимости открытых рыночных счетов ТОЙ ЖЕ валюты. Кросс-валютные
    /// позиции сюда не подмешиваем без конвертации — это была бы неверная цифра, а не «примерная»
    /// (см. брифинг: «если источника нет — не выдумывай»). `nil`, если сравнивать не с чем.
    /// Расчёт живёт в `MarketPortfolioValuation`: обзор портфеля обязан показывать ту же долю.
    var portfolioSharePercent: Decimal? {
        guard account.kind == .marketInvestment else { return nil }
        return MarketPortfolioValuation(modelContext: modelContext)
            .sharePercent(of: balanceToday, currency: account.currency)
    }
}
