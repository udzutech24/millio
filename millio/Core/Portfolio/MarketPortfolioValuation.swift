//
//  MarketPortfolioValuation.swift
//  millio
//

import Foundation
import SwiftData

/// Стоимость рыночных позиций и их доля в портфеле одной валюты — один расчёт для экрана позиции и AI-дайджеста.
@MainActor
struct MarketPortfolioValuation {
    let modelContext: ModelContext
    var now: Date = Date()

    /// Активные рыночные счета валюты `currency` — ровно тот круг, среди которого экран позиции
    /// считает «Долю в портфеле». Кросс-валютные позиции без конвертации сюда не подмешиваем:
    /// это была бы неверная цифра, а не «примерная».
    func peers(currency: String) -> [Account] {
        activeMarketAccounts().filter { $0.currency == currency }
    }

    /// Активные рыночные счета всех валют.
    func activeMarketAccounts() -> [Account] {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.kindRaw == "marketInvestment" })
        guard let candidates = try? modelContext.fetch(descriptor) else { return [] }
        return candidates.filter { $0.archivedAt == nil && $0.deletedAt == nil }
    }

    /// Знаменатель «Доли в портфеле»: FIFO-количество × цена по цепочке фолбэков.
    func portfolioTotal(currency: String) -> Decimal {
        peers(currency: currency).reduce(Decimal.zero) { sum, account in
            guard let symbol = account.marketMeta?.symbol, !symbol.isEmpty,
                  let snapshot = try? StockLotEngine.replay(events: account.events ?? [], on: now) else { return sum }
            return sum + snapshot.quantity * liveOrCachedPrice(symbol: symbol, events: account.events ?? [])
        }
    }

    /// Доля стоимости позиции в портфеле её валюты. `nil`, если сравнивать не с чем.
    func sharePercent(of value: Decimal, currency: String) -> Decimal? {
        let total = portfolioTotal(currency: currency)
        guard total > 0 else { return nil }
        return (value / total) * 100
    }

    /// Подтверждённый баланс счёта на `now`: hero экрана любого счёта (`AccountDetailView.balanceToday`),
    /// у рыночного — «Стоимость позиции» с тем же снэпшотом кэша цен. Формула одна для экрана и
    /// дайджеста; рыночных сокращений сюда не добавлять — ею же считаются вклад, карта и наличные.
    func positionValue(of account: Account) -> Decimal {
        AccountBalanceEngine.balanceAt(
            events: confirmedEvents(of: account),
            kind: account.kind,
            on: now,
            priceProvider: priceProvider(for: account),
            marketMeta: account.marketMeta
        )
    }

    /// Количество, из которого движок получил стоимость позиции.
    func quantity(of account: Account) -> Decimal {
        AccountBalanceEngine.marketQuantityAt(events: confirmedEvents(of: account), on: now)
    }

    /// Цена единицы на дату так, как её видит движок: кэш котировок с форвард-филлом, иначе цена
    /// последней сделки не позже даты. `nil`, если позиции на эту дату ещё не было.
    func unitPrice(of account: Account, on date: Date) -> Decimal? {
        let events = confirmedEvents(of: account)
        let quantity = AccountBalanceEngine.marketQuantityAt(events: events, on: date)
        guard quantity > 0 else { return nil }
        let value = AccountBalanceEngine.balanceAt(
            events: events,
            kind: account.kind,
            on: date,
            priceProvider: priceProvider(for: account),
            marketMeta: account.marketMeta
        )
        return value / quantity
    }

    /// Цепочка фолбэков цены: сегодняшняя котировка → последняя из кэша → последняя цена buy/sell.
    func liveOrCachedPrice(symbol: String, events: [AccountEvent]) -> Decimal {
        let upper = symbol.uppercased()
        let dayKey = AccountEvent.dayKey(for: now)
        let todayDescriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper && $0.dayKey == dayKey }
        )
        if let today = try? modelContext.fetch(todayDescriptor).first { return today.price }
        let cachedDescriptor = FetchDescriptor<HistoricalAssetPrice>(
            predicate: #Predicate<HistoricalAssetPrice> { $0.symbol == upper },
            sortBy: [SortDescriptor(\.dayKey, order: .reverse)]
        )
        if let cached = try? modelContext.fetch(cachedDescriptor).first { return cached.price }
        return events
            .sorted { $0.date < $1.date }
            .last(where: { ($0.type == .buy || $0.type == .sell) && $0.unitPrice != nil })?
            .unitPrice ?? 0
    }

    // MARK: - Private

    private func confirmedEvents(of account: Account) -> [AccountEvent] {
        DepositConfirmedBalanceResolver.confirmedEvents(account.events ?? [], accountID: account.id, kind: account.kind)
    }

    private func priceProvider(for account: Account) -> MarketPriceProviding? {
        guard account.kind == .marketInvestment, let meta = account.marketMeta else { return nil }
        return AccountMarketPriceService(modelContext: modelContext).makeSnapshotProvider(symbols: [meta.symbol])
    }
}
