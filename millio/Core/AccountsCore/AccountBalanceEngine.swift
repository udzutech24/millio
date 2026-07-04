import Foundation

/// Источник рыночной цены на дату (котировки акций/крипты/облигаций/металлов).
/// В Фазе 0 — только протокол; реальная реализация (кэш котировок) — в следующих фазах.
protocol MarketPriceProviding {
    func price(symbol: String, assetClass: MarketAssetClass, on date: Date) -> Decimal?
}

/// Чистая логика реплея событий в баланс на дату. НЕ делает SwiftData-fetch —
/// принимает уже загруженный массив событий (вызывающий код сам решает откуда их взять,
/// напр. инкрементально от последнего снапшота — Фаза 1+).
/// Единственная функция истины для тотала/дельты/графика/снапшота (AC2).
enum AccountBalanceEngine {

    /// Баланс счёта на дату `date` по массиву его событий.
    /// `marketMeta` нужен только движку E (symbol/assetClass для `priceProvider`); для остальных kind игнорируется.
    /// - Important: сортировка строго детерминирована (date, createdAt, id) — S5.
    static func balanceAt(
        events: [AccountEvent],
        kind: AccountKind,
        on date: Date,
        priceProvider: MarketPriceProviding? = nil,
        marketMeta: MarketMeta? = nil
    ) -> Decimal {
        let relevant = events
            .filter { $0.date <= date }
            .sorted(by: strictOrder)

        let transformed = applyRedenomination(to: relevant)

        switch kind.engine {
        case .cashLike, .deposit, .debt:
            // A/B/D: генерик знаковая сумма ленты событий. Знак долга (D) задаётся
            // создателем событий (openingBalance со знаком) — движок одинаковый с A.
            return ledgerSum(transformed, signMap: cashLikeSignMap)
        case .loan:
            // C: обязательство — выдачи увеличивают долг (отрицательно), платежи уменьшают. Не обрезаем нулём.
            return ledgerSum(transformed, signMap: loanSignMap)
        case .market:
            return marketBalance(transformed, priceProvider: priceProvider, marketMeta: marketMeta)
        case .manualAsset:
            return manualAssetBalance(transformed)
        }
    }

    // MARK: - Сортировка (S5: детерминизм реплея)

    private static func strictOrder(_ lhs: AccountEvent, _ rhs: AccountEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    // MARK: - Redenomination (AC11/AC15): единая точка правды для всех движков

    /// Транзитное значение события ПОСЛЕ конвертации курсом редоминации.
    /// amount/unitPrice масштабируются кумулятивным произведением курсов всех
    /// redenomination-событий, случившихся СТРОГО ПОЗЖЕ этого события (в пределах `date`).
    /// quantity (штуки актива) редоминации не подлежит — это не денежная величина.
    private struct TransformedEvent {
        let type: AccountEventType
        let amount: Decimal?
        let quantity: Decimal?
        let unitPrice: Decimal?
        let date: Date
    }

    private static func applyRedenomination(to sorted: [AccountEvent]) -> [TransformedEvent] {
        var result = [TransformedEvent](repeating: TransformedEvent(type: .adjustment, amount: nil, quantity: nil, unitPrice: nil, date: .distantPast), count: sorted.count)
        var multiplier: Decimal = 1
        // Идём с конца к началу: multiplier на момент события = произведение курсов всех
        // более поздних redenomination-событий (событие редоминации само себя не масштабирует).
        for index in stride(from: sorted.count - 1, through: 0, by: -1) {
            let event = sorted[index]
            result[index] = TransformedEvent(
                type: event.type,
                amount: event.amount.map { $0 * multiplier },
                quantity: event.quantity,
                unitPrice: event.unitPrice.map { $0 * multiplier },
                date: event.date
            )
            if event.type == .redenomination, let rate = event.redenomRate {
                multiplier *= rate
            }
        }
        return result
    }

    // MARK: - Ленточные знаковые суммы (A/B/D и C)

    private static func ledgerSum(_ events: [TransformedEvent], signMap: (AccountEventType) -> Decimal) -> Decimal {
        events.reduce(Decimal(0)) { acc, event in
            acc + (event.amount ?? 0) * signMap(event.type)
        }
    }

    /// A/B/D: opening/income/transferIn/interest/dividend/extraPayment — плюс; expense/transferOut/fee — минус;
    /// adjustment — дельта как есть (знак хранит создатель события).
    private static func cashLikeSignMap(_ type: AccountEventType) -> Decimal {
        switch type {
        case .openingBalance, .income, .transferIn, .interest, .dividend, .extraPayment, .adjustment:
            return 1
        case .expense, .transferOut, .fee:
            return -1
        case .buy, .sell, .rollover, .revaluation, .redenomination:
            return 0
        }
    }

    /// C: openingBalance/expense — рост долга (минус); income/extraPayment — погашение (плюс);
    /// interest/fee — рост долга (минус); adjustment — дельта как есть.
    private static func loanSignMap(_ type: AccountEventType) -> Decimal {
        switch type {
        case .openingBalance, .expense, .interest, .fee:
            return -1
        case .income, .extraPayment, .transferIn, .adjustment:
            return 1
        case .transferOut:
            return -1
        case .dividend, .buy, .sell, .rollover, .revaluation, .redenomination:
            return 0
        }
    }

    // MARK: - E: рыночный счёт

    private static func marketBalance(
        _ events: [TransformedEvent],
        priceProvider: MarketPriceProviding?,
        marketMeta: MarketMeta?
    ) -> Decimal {
        let quantity = events.reduce(Decimal(0)) { acc, event in
            switch event.type {
            case .buy: return acc + (event.quantity ?? 0)
            case .sell: return acc - (event.quantity ?? 0)
            default: return acc
            }
        }

        guard quantity != 0 else { return 0 }

        let asOfDate = events.last?.date ?? Date()
        let providedPrice = marketMeta.flatMap { meta in
            priceProvider?.price(symbol: meta.symbol, assetClass: meta.assetClass, on: asOfDate)
        }

        let lastKnownPrice = events.reversed().first { event in
            switch event.type {
            case .buy, .sell, .revaluation: return event.unitPrice != nil
            default: return false
            }
        }?.unitPrice

        let price = providedPrice ?? lastKnownPrice ?? 0
        return quantity * price
    }

    // MARK: - F: ручной актив

    private static func manualAssetBalance(_ events: [TransformedEvent]) -> Decimal {
        if let lastRevaluation = events.reversed().first(where: { $0.type == .revaluation }) {
            return lastRevaluation.amount ?? 0
        }
        if let lastOpening = events.reversed().first(where: { $0.type == .openingBalance }) {
            return lastOpening.amount ?? 0
        }
        return 0
    }
}
