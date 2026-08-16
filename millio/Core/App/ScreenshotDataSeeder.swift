//
//  ScreenshotDataSeeder.swift
//  millio
//
//  Засевает реалистичные mock-данные для автоматических App Store скриншотов.
//  Используется ТОЛЬКО при MILLIO_SCREENSHOT_MODE=1 (fastlane snapshot).
//

import Foundation
import SwiftData

// Локаль для засева данных. Расширяй по мере добавления языков в Snapfile.
enum SeedLocale: Equatable {
    case russian
    case english
    // case german   // de → EUR, Deutsche Bank / Sparkasse
    // case chinese  // zh-Hans → CNY, 工商银行 / 建设银行

    static var current: SeedLocale {
        let lang = Locale.preferredLanguages.first ?? ""
        if lang.hasPrefix("en") { return .english }
        return .russian
    }

    var currency: String {
        switch self {
        case .english: return "USD"
        case .russian: return "RUB"
        }
    }

    /// Обратная совместимость с ternary-паттернами внутри seeder
    var isEN: Bool { self == .english }
}

@MainActor
enum ScreenshotDataSeeder {

    static func seed(into context: ModelContext) async {
        purgeAll(context)
        let locale = SeedLocale.current
        seedSettings(locale: locale)
        let cards = seedCards(into: context, locale: locale)
        let investments = seedInvestments(into: context, locale: locale)
        seedGroups(into: context, cards: cards, investmentIDs: investments, locale: locale)
        seedCashback(into: context, cards: cards, locale: locale)
        seedCashflowTransactions(into: context,
                                 debitCardID: cards.debit.uniqueID,
                                 creditCardID: cards.credit.uniqueID,
                                 locale: locale)
        try? context.save()
        // AccountsCore — новое ядро счетов (rebuild 2026-07): экраны «Финансы»/Дашборд считают
        // баланс через AccountsTotalsService.totalAt по Account/AccountGroup, легаси-модели выше
        // (Card/Investment) в тотал уже не входят. Без этого шага скриншоты показывали 0 ₽/пустой
        // список продуктов, хотя легаси-сид отрабатывал штатно.
        #if DEBUG
        _ = try? AccountsCoreSeeder.seedDemoPortfolio(context: context, isEN: locale.isEN)
        // Историческая оценка (HistoricalValuationResolver) работает fail-closed: если хотя бы одна
        // зависимость дня (курс валюты или котировка) не имеет evidence, обнуляется ВЕСЬ портфель
        // за этот день, и «Динамика» рисует пустой стейт «Нет групп». В симуляторе сети нет,
        // провайдеры молчат — поэтому evidence надо положить локально ДО rebuild.
        seedHistoricalValuationEvidence(into: context)
        // Карточка «Динамика» строит график/группировку по `AccountDailySnapshot`, а не по
        // событиям напрямую (см. `AccountSnapshotRebuilder` докстринг) — без явного rebuild
        // счета, которые только что создал seedDemoPortfolio, остаются без единого снапшота,
        // и экран показывает «Нет данных для отображения». `AccountSnapshotBackfillCoordinator`
        // не подходит: он per-scope gate-ится через UserDefaults-флаг, который может быть уже
        // взведён с прошлого запуска на симуляторе — тогда бэкфилл тихо не выполнится. Здесь же
        // нужен безусловный прогон при каждом сиде, поэтому напрямую `rebuildAllAccounts()`.
        let rebuilder = AccountSnapshotRebuilder(modelContainer: context.container)
        _ = try? await rebuilder.rebuildAllAccounts()
        #endif
    }

    // MARK: - Historical valuation evidence (FX + котировки)

    #if DEBUG
    /// Кладёт синтетическую exact-evidence на каждый день окна графика «Динамика».
    ///
    /// Формат `source` критичен и должен совпадать с тем, что распознаёт
    /// `HistoricalValuationLocalEvidenceSnapshot`: у FX — префикс `historical` + `rateDate`
    /// строго в начале дня; у котировок — `historical:<provider>|tz=<IANA>` с той же таймзоной,
    /// что у `HistoricalValuationTimeContext` (иначе строка молча отбрасывается как legacy).
    private static func seedHistoricalValuationEvidence(into context: ModelContext) {
        let calendar = Calendar.current
        let timeZoneID = TimeZone.current.identifier
        let now = Date()
        let today = calendar.startOfDay(for: now)

        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.calendar = calendar
        dayKeyFormatter.timeZone = calendar.timeZone
        dayKeyFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"

        // Валюты демо-портфеля (AccountsCoreSeeder): RUB (основная), USD, EUR.
        // base, quote, курс сегодня, дневной дрейф в прошлое
        let fxPairs: [(base: String, quote: String, rate: Double, drift: Double)] = [
            ("USD", "RUB", 92.50, 0.030),
            ("EUR", "RUB", 100.20, 0.034),
            ("USD", "EUR", 0.92, 0.0003)
        ]
        // Тикеры демо-портфеля: AAPL (100 шт), NVDA (20 шт).
        let tickers: [(symbol: String, price: Double, drift: Double)] = [
            ("AAPL", 214.0, 0.11),
            ("NVDA", 1_180.0, 0.62)
        ]

        // 400 дней покрывают все диапазоны карточки, включая 1Y.
        for offset in 0..<400 {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let dayKey = dayKeyFormatter.string(from: day)
            // Полдень дня наблюдения, но не в будущем — иначе строка «сегодня» выглядит нереалистично.
            let fetchedAt = min(day.addingTimeInterval(12 * 3600), now)
            let age = Double(offset)

            for pair in fxPairs {
                context.insert(HistoricalRate(
                    baseCurrency: pair.base,
                    quoteCurrency: pair.quote,
                    rate: pair.rate - pair.drift * age,
                    rateDate: day,
                    source: "historical:screenshot-seed",
                    fetchedAt: fetchedAt
                ))
            }

            for ticker in tickers {
                context.insert(HistoricalAssetPrice(
                    symbol: ticker.symbol,
                    assetClass: .stock,
                    dayKey: dayKey,
                    price: Decimal(ticker.price - ticker.drift * age),
                    source: "historical:screenshot-seed|tz=\(timeZoneID)",
                    fetchedAt: fetchedAt
                ))
            }
        }
        try? context.save()
    }
    #endif

    // MARK: - Settings (UserDefaults)

    private static func seedSettings(locale: SeedLocale) {
        let defaults = UserDefaults.standard
        // Принудительно задаём primaryCurrency — иначе значение из предыдущего locale-запуска
        // может остаться в UserDefaults (например, USD после EN-прогона persist'ится на RU-прогон)
        defaults.set(locale.currency, forKey: "primaryCurrencyCode")
        let favorites: [String] = locale.isEN
            ? ["USD", "EUR", "GBP", "JPY", "CAD"]
            : ["RUB", "USD", "EUR", "CNY", "TRY"]
        defaults.set(favorites, forKey: "favoriteCurrencyCodes")
        // Конвертер использует собственный ключ — отдельно от favoriteCurrencyCodes
        let converterCodes = locale.isEN ? "USD,EUR,GBP,JPY,CAD" : "RUB,USD,EUR,TRY,GBP,KZT"
        defaults.set(converterCodes, forKey: "conv_selected_codes")
        // Dashboard: показываем все 4 виджета чтобы экран выглядел заполненным
        let allWidgets = ["totalBalance", "cashflowSummary", "currencyRates", "quickActions"]
        if let data = try? JSONEncoder().encode(allWidgets) {
            defaults.set(data, forKey: "dashboard.active_widgets.v1")
        }
        // Card 06: seed курсов конвертера — без этого экран показывает 0 и error toast
        // Формат: "CODE": value означает 1 USD = value CODE
        // Ключи conv_cached_rates_millio / conv_last_rates_ts_millio — из CurrencyWidgetShared.Keys
        let seedRates: [String: Double] = [
            "USD": 1.0,
            "EUR": 0.92,
            "GBP": 0.78,
            "JPY": 155.20,
            "CAD": 1.36,
            "TRY": 38.50,
            "RUB": 92.50,
            "CNY": 7.25,
            "KZT": 520.0,
            "CHF": 0.89,
            "AUD": 1.55,
        ]
        defaults.set(seedRates, forKey: "conv_cached_rates_millio")
        defaults.set(Date().timeIntervalSince1970, forKey: "conv_last_rates_ts_millio")
    }

    // MARK: - Purge

    private static func purgeAll(_ context: ModelContext) {
        try? context.delete(model: FinanceAccount.self)
        try? context.delete(model: FinanceGroup.self)
        try? context.delete(model: Card.self)
        try? context.delete(model: Investment.self)
        try? context.delete(model: Cashback.self)
        try? context.delete(model: CashflowTransaction.self)
        // AccountsCore — иначе идемпотентный маркер AccountsCoreSeeder переживает purge и
        // повторный прогон (EN после RU в той же UI-тест-сессии) молча не досеивает данные.
        try? context.delete(model: AccountEvent.self)
        try? context.delete(model: HistoricalAssetPrice.self)
        try? context.delete(model: AccountDailySnapshot.self)
        try? context.delete(model: Account.self)
        try? context.delete(model: AccountGroup.self)
    }

    // MARK: - Cards

    struct SeedCards {
        let debit: Card
        let secondary: Card
        let credit: Card
        let savings: Card
        let foreign: Card
    }

    @discardableResult
    private static func seedCards(into context: ModelContext, locale: SeedLocale) -> SeedCards {
        let isEN = locale.isEN
        let primary = Card(
            name: isEN ? "Chase Sapphire" : "Tinkoff Black",
            cardNumber: "4273",
            bank: isEN ? .other : .tinkoff,
            cardType: .debit,
            priority: .high,
            currency: isEN ? "USD" : "RUB",
            balance: isEN ? 8_420 : 312_480,
            isFavorite: true
        )

        let secondary = Card(
            name: isEN ? "Bank of America" : "Сбербанк",
            cardNumber: "6390",
            bank: isEN ? .other : .sberbank,
            cardType: .debit,
            priority: .normal,
            currency: isEN ? "USD" : "RUB",
            balance: isEN ? 3_150 : 87_250
        )

        let credit = Card(
            name: isEN ? "Amex Gold" : "Alfa Black",
            cardNumber: "5591",
            bank: isEN ? .other : .alfa,
            cardType: .credit,
            priority: .normal,
            currency: isEN ? "USD" : "RUB",
            balance: isEN ? -1_840 : -45_600,
            creditLimit: isEN ? 10_000 : 200_000
        )

        let savings = Card(
            name: isEN ? "Savings Account" : "Накопительный",
            cardNumber: "8821",
            bank: isEN ? .other : .sberbank,
            cardType: .debit,
            priority: .normal,
            currency: isEN ? "USD" : "RUB",
            balance: isEN ? 15_000 : 540_000
        )

        let foreign = Card(
            name: isEN ? "Wise EUR" : "Raiffeisen EUR",
            cardNumber: "4897",
            bank: isEN ? .other : .raiffeisen,
            cardType: .debit,
            priority: .low,
            currency: "EUR",
            balance: isEN ? 1_200 : 2_840
        )

        context.insert(primary)
        context.insert(secondary)
        context.insert(credit)
        context.insert(savings)
        context.insert(foreign)
        return SeedCards(debit: primary, secondary: secondary, credit: credit,
                         savings: savings, foreign: foreign)
    }

    // MARK: - Investments

    private static func seedInvestments(into context: ModelContext, locale: SeedLocale) -> [String] {
        let isEN = locale.isEN
        let stock1 = Investment(
            name: isEN ? "Apple Inc." : "AAPL",
            investmentType: .positive,
            category: .stocks,
            amount: isEN ? 24_850 : 179_210,
            currency: isEN ? "USD" : "RUB",
            includeInTotal: true,
            priority: .high,
            isFavorite: true
        )
        stock1.marketSymbol = "AAPL"
        stock1.marketQuantity = isEN ? 12 : 7
        stock1.averagePurchaseUnitPrice = isEN ? 178 : 22_400
        stock1.lastKnownUnitPrice = isEN ? 207.1 : 25_600
        stock1.totalPurchaseCost = isEN ? 2_136 : 156_800

        let stock2 = Investment(
            name: isEN ? "Sberbank ADR" : "SBER",
            investmentType: .positive,
            category: .stocks,
            amount: isEN ? 3_280 : 65_300,
            currency: isEN ? "USD" : "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        stock2.marketSymbol = isEN ? "SBER" : "SBER"
        stock2.marketQuantity = 200
        stock2.averagePurchaseUnitPrice = isEN ? 14.5 : 290
        stock2.lastKnownUnitPrice = isEN ? 16.4 : 326.5
        stock2.totalPurchaseCost = isEN ? 2_900 : 58_000

        let crypto = Investment(
            name: "Bitcoin",
            investmentType: .positive,
            category: .crypto,
            amount: isEN ? 5_180 : 412_000,
            currency: isEN ? "USD" : "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        crypto.marketSymbol = "BTC"
        crypto.marketQuantity = 0.05
        crypto.averagePurchaseUnitPrice = isEN ? 68_000 : 6_800_000
        crypto.lastKnownUnitPrice = isEN ? 103_600 : 8_240_000
        crypto.totalPurchaseCost = isEN ? 3_400 : 340_000

        let etf = Investment(
            name: isEN ? "S&P 500 ETF" : "FXUS ETF",
            investmentType: .positive,
            category: .stocks,
            amount: isEN ? 7_420 : 83_500,
            currency: isEN ? "USD" : "RUB",
            includeInTotal: true,
            priority: .normal,
            isFavorite: false
        )
        etf.marketSymbol = isEN ? "SPY" : "FXUS"
        etf.marketQuantity = isEN ? 15 : 120
        etf.averagePurchaseUnitPrice = isEN ? 460 : 620
        etf.lastKnownUnitPrice = isEN ? 494.8 : 695.8
        etf.totalPurchaseCost = isEN ? 6_900 : 74_400

        context.insert(stock1)
        context.insert(stock2)
        context.insert(crypto)
        context.insert(etf)
        return [stock1.uniqueID, stock2.uniqueID, crypto.uniqueID, etf.uniqueID]
    }

    // MARK: - Groups (FinanceGroup + FinanceAccount)

    private static func seedGroups(
        into context: ModelContext,
        cards: SeedCards,
        investmentIDs: [String],
        locale: SeedLocale
    ) {
        let isEN = locale.isEN
        func account(_ type: FinanceAccountType, _ id: String, group: FinanceGroup, order: Int) {
            let a = FinanceAccount(accountType: type, accountID: id)
            a.group = group; a.order = order; context.insert(a)
        }

        // Group 1 — ежедневные счета
        let g1 = FinanceGroup(name: isEN ? "Daily Accounts" : "Основные счета",
                              colorHex: "#34C759", order: 0, isFavorite: true, priority: .high)
        context.insert(g1)
        account(.card, cards.debit.uniqueID, group: g1, order: 0)
        account(.card, cards.secondary.uniqueID, group: g1, order: 1)

        // Group 2 — накопления
        let g2 = FinanceGroup(name: isEN ? "Savings" : "Накопления",
                              colorHex: "#30B0C7", order: 1, isFavorite: false, priority: .normal)
        context.insert(g2)
        account(.card, cards.savings.uniqueID, group: g2, order: 0)
        account(.card, cards.foreign.uniqueID, group: g2, order: 1)

        // Group 3 — кредитная карта (тип .card — Alfa Black это Card с cardType: .credit)
        let g3 = FinanceGroup(name: isEN ? "Credit Cards" : "Кредитные карты",
                              colorHex: "#FF9F0A", order: 2, priority: .normal)
        context.insert(g3)
        account(.card, cards.credit.uniqueID, group: g3, order: 0)

        // Group 4 — инвестиции
        let g4 = FinanceGroup(name: isEN ? "Investments" : "Инвестиции",
                              colorHex: "#5E5CE6", order: 3, isFavorite: true, priority: .high)
        context.insert(g4)
        for (i, invID) in investmentIDs.enumerated() {
            account(.investment, invID, group: g4, order: i)
        }
    }

    // MARK: - Cashback

    private static func seedCashback(into context: ModelContext, cards: SeedCards, locale: SeedLocale) {
        let monthKey = Cashback.monthKey(for: Date())

        // Три банка с разными категориями — подтверждает буллет «Несколько банков сразу»
        // Card 1 (primary debit): высокодоходные категории
        let primaryItems: [(CashbackCategory, Double)] = [
            (.carSharing, 10),
            (.pharmacy, 5),
            (.taxi, 5),
            (.autoServices, 5),
        ]
        // Card 2 (secondary debit): транспорт и досуг
        let secondaryItems: [(CashbackCategory, Double)] = [
            (.railway, 4),
            (.restaurant, 3),
            (.airlines, 3),
        ]
        // Card 3 (credit): базовые категории
        let creditItems: [(CashbackCategory, Double)] = [
            (.healthcare, 3),
            (.supermarket, 2),
            (.transport, 2),
        ]

        for (category, pct) in primaryItems {
            context.insert(Cashback(name: category.displayName, category: category,
                                    percentage: pct, cardIDs: [cards.debit.uniqueID], monthKey: monthKey))
        }
        for (category, pct) in secondaryItems {
            context.insert(Cashback(name: category.displayName, category: category,
                                    percentage: pct, cardIDs: [cards.secondary.uniqueID], monthKey: monthKey))
        }
        for (category, pct) in creditItems {
            context.insert(Cashback(name: category.displayName, category: category,
                                    percentage: pct, cardIDs: [cards.credit.uniqueID], monthKey: monthKey))
        }
    }

    // MARK: - Cashflow Transactions

    private static func seedCashflowTransactions(
        into context: ModelContext,
        debitCardID: String,
        creditCardID: String,
        locale: SeedLocale
    ) {
        let isEN = locale.isEN
        var cal = Calendar.current
        cal.timeZone = TimeZone(identifier: "UTC")!

        func date(monthsAgo: Int, day: Int) -> Date {
            let now = Date()
            let base = cal.date(byAdding: .month, value: -monthsAgo, to: now)!
            var comps = cal.dateComponents([.year, .month], from: base)
            comps.day = day
            return cal.date(from: comps) ?? base
        }

        // 6 месяцев зарплат (рост)
        let salaries: [(Int, Double)] = [
            (5, isEN ? 6_500 : 125_000),
            (4, isEN ? 6_500 : 125_000),
            (3, isEN ? 7_200 : 135_000),
            (2, isEN ? 7_200 : 135_000),
            (1, isEN ? 7_800 : 140_000),
            (0, isEN ? 7_800 : 140_000),
        ]
        for (monthsAgo, amount) in salaries {
            let t = CashflowTransaction(
                transactionType: .income, amount: amount,
                currency: isEN ? "USD" : "RUB",
                transactionDate: date(monthsAgo: monthsAgo, day: 5),
                cardID: debitCardID, incomeCategory: .salary
            )
            context.insert(t)
        }

        // Фриланс / Side income
        let freelances: [(Int, Double)] = [
            (4, isEN ? 1_400 : 28_000),
            (2, isEN ? 1_750 : 35_000),
            (1, isEN ? 900 : 18_000),
            (0, isEN ? 2_100 : 42_000),
        ]
        for (monthsAgo, amount) in freelances {
            let t = CashflowTransaction(
                transactionType: .income, amount: amount,
                currency: isEN ? "USD" : "RUB",
                transactionDate: date(monthsAgo: monthsAgo, day: 20),
                cardID: debitCardID, incomeCategory: .freelance
            )
            context.insert(t)
        }

        // Дивиденды
        for (monthsAgo, amount) in [(2, isEN ? 210.0 : 4_200.0), (5, isEN ? 180.0 : 3_600.0)] {
            let t = CashflowTransaction(
                transactionType: .income, amount: amount,
                currency: isEN ? "USD" : "RUB",
                transactionDate: date(monthsAgo: monthsAgo, day: 15),
                cardID: debitCardID, incomeCategory: .dividends
            )
            context.insert(t)
        }

        // Бонус
        let bonus = CashflowTransaction(
            transactionType: .income, amount: isEN ? 1_200 : 25_000,
            currency: isEN ? "USD" : "RUB",
            transactionDate: date(monthsAgo: 1, day: 28),
            cardID: debitCardID, incomeCategory: .bonus
        )
        context.insert(bonus)

        // Регулярные расходы × 6 месяцев
        let monthlyExpenses: [(ExpenseCategory, Double, Int, String?)] = [
            (.groceries,    isEN ? 620 : 18_400,  3, nil),
            (.dining,       isEN ? 310 : 9_200,   7, nil),
            (.transport,    isEN ? 95  : 3_100,   9, nil),
            (.utilities,    isEN ? 180 : 6_800,  10, nil),
            (.telecom,      isEN ? 55  : 1_200,  12, nil),
            (.subscriptions,isEN ? 28  : 890,    14, isEN ? "Netflix, Spotify" : "Netflix, Spotify"),
            (.pharmacy,     isEN ? 75  : 2_300,  18, nil),
            (.clothing,     isEN ? 480 : 14_700, 22, nil),
            (.entertainment,isEN ? 145 : 4_500,  25, nil),
            (.health,       isEN ? 120 : 3_800,  17, nil),
            (.beauty,       isEN ? 90  : 2_600,  21, nil),
        ]

        for monthsAgo in 0..<6 {
            for (cat, baseAmount, day, note) in monthlyExpenses {
                let variance = Double.random(in: 0.82...1.18)
                let amount = (baseAmount * variance).rounded()
                let t = CashflowTransaction(
                    transactionType: .expense, amount: amount,
                    currency: isEN ? "USD" : "RUB",
                    transactionDate: date(monthsAgo: monthsAgo, day: day),
                    cardID: debitCardID, expenseCategory: cat, note: note
                )
                context.insert(t)
            }
        }

        // Крупные разовые расходы
        let oneOff: [(ExpenseCategory, Double, Int, Int, String?)] = [
            (.travel,      isEN ? 2_100 : 87_000, 3, 15, isEN ? "Turkey trip" : "Турция"),
            (.electronics, isEN ? 1_850 : 62_500, 4,  8, isEN ? "MacBook Pro" : "MacBook Pro"),
            (.health,      isEN ? 380  : 12_400,  2, 20, nil),
            (.homeGoods,   isEN ? 720  : 23_800,  1,  5, nil),
            (.education,   isEN ? 499  : 18_000,  5,  1, isEN ? "Course" : "Курс"),
            (.dining,      isEN ? 185  : 6_200,   0, 10, isEN ? "Restaurant" : "Ресторан"),
        ]
        for (cat, amount, monthsAgo, day, note) in oneOff {
            let t = CashflowTransaction(
                transactionType: .expense, amount: amount,
                currency: isEN ? "USD" : "RUB",
                transactionDate: date(monthsAgo: monthsAgo, day: day),
                cardID: debitCardID, expenseCategory: cat, note: note
            )
            context.insert(t)
        }

        // Переводы между счетами (с operationGroupID — отображаются как группа)
        let transferGroupID1 = UUID().uuidString
        let transferOut = CashflowTransaction(
            transactionType: .transfer,
            amount: isEN ? 500 : 20_000,
            currency: isEN ? "USD" : "RUB",
            transactionDate: date(monthsAgo: 0, day: 3),
            cardID: debitCardID,
            expenseCategory: .transfers,
            note: isEN ? "To savings" : "На накопительный",
            operationGroupID: transferGroupID1
        )
        let transferIn = CashflowTransaction(
            transactionType: .income,
            amount: isEN ? 500 : 20_000,
            currency: isEN ? "USD" : "RUB",
            transactionDate: date(monthsAgo: 0, day: 3),
            cardID: creditCardID,
            incomeCategory: .other,
            note: isEN ? "From main" : "С основного",
            operationGroupID: transferGroupID1
        )
        context.insert(transferOut)
        context.insert(transferIn)

        // Ещё один перевод (прошлый месяц)
        let transferGroupID2 = UUID().uuidString
        let transfer2Out = CashflowTransaction(
            transactionType: .transfer,
            amount: isEN ? 800 : 30_000,
            currency: isEN ? "USD" : "RUB",
            transactionDate: date(monthsAgo: 1, day: 18),
            cardID: debitCardID,
            expenseCategory: .transfers,
            note: isEN ? "Credit repayment" : "Погашение кредита",
            operationGroupID: transferGroupID2
        )
        let transfer2In = CashflowTransaction(
            transactionType: .income,
            amount: isEN ? 800 : 30_000,
            currency: isEN ? "USD" : "RUB",
            transactionDate: date(monthsAgo: 1, day: 18),
            cardID: creditCardID,
            incomeCategory: .other,
            note: isEN ? "Card payment" : "Оплата карты",
            operationGroupID: transferGroupID2
        )
        context.insert(transfer2Out)
        context.insert(transfer2In)
    }
}
