//
//  FinanceTotalsService.swift
//  millio
//
//  Создан как часть декомпозиции FinanceViewModel (Phase 11).
//  Содержит расчёт суммарных балансов по группам и общего баланса,
//  конвертацию валют между счетами.
//

import Foundation

/// Снимок результатов расчёта общего баланса.
struct FinanceTotalsSnapshot {
    var totalAmount: Double
    var secondaryTotalAmount: Double
    var currencyConversionWarning: String?
}

@MainActor
final class FinanceTotalsService {

    // MARK: - Зависимости

    private let currencyService: CurrencyRateServiceProtocol

    // Провайдеры состояния
    private let groupsProvider: () -> [FinanceGroup]
    private let displayCurrencyProvider: () -> String
    private let secondaryDisplayCurrencyProvider: () -> String?
    private let cardByIDProvider: () -> [String: Card]
    private let creditByIDProvider: () -> [String: Credit]
    private let investmentByIDProvider: () -> [String: Investment]
    /// Единственный источник агрегата «Общий баланс» (6b Фаза 2, single-world) —
    /// `AccountsTotalsService.totalAt(date, in:)`. С Фазы 2 легаси-мир мигрирован в ядро и скрыт
    /// (`archivedAt`), поэтому агрегат считается только по ядру; легаси-цикл по группам снят.
    /// Заголовок «Динамика» после Фазы 2 сводится к тому же вкладу (`totalAt`), закрывая R1
    /// аудита 2026-07-02 (три пути тотала → один).
    private let newCoreTotalProvider: (String) async -> Decimal

    // MARK: - Init

    init(
        currencyService: CurrencyRateServiceProtocol,
        groupsProvider: @escaping () -> [FinanceGroup],
        displayCurrencyProvider: @escaping () -> String,
        secondaryDisplayCurrencyProvider: @escaping () -> String?,
        cardByIDProvider: @escaping () -> [String: Card],
        creditByIDProvider: @escaping () -> [String: Credit],
        investmentByIDProvider: @escaping () -> [String: Investment],
        newCoreTotalProvider: @escaping (String) async -> Decimal = { _ in 0 }
    ) {
        self.currencyService = currencyService
        self.groupsProvider = groupsProvider
        self.displayCurrencyProvider = displayCurrencyProvider
        self.secondaryDisplayCurrencyProvider = secondaryDisplayCurrencyProvider
        self.cardByIDProvider = cardByIDProvider
        self.creditByIDProvider = creditByIDProvider
        self.investmentByIDProvider = investmentByIDProvider
        self.newCoreTotalProvider = newCoreTotalProvider
    }

    // MARK: - Public: Расчёт общего баланса

    /// Single-world (6b Фаза 2): агрегат «Общий баланс» = сумма по счетам ЯДРА в валюте экрана,
    /// одной точкой `AccountsTotalsService.totalAt(now)`. Легаси-мир мигрирован и скрыт, поэтому
    /// прежний цикл суммирования групп (легаси + core-ламп) снят — остаётся единственный источник.
    /// Конвертация валют выполняется внутри ядра, поэтому агрегат сам по себе предупреждений о
    /// курсах не порождает (per-group display считает `calculateGroupTotal` отдельно).
    func calculateTotalsSnapshot() async -> FinanceTotalsSnapshot {
        let displayCurrency = displayCurrencyProvider()
        let total = NSDecimalNumber(decimal: await newCoreTotalProvider(displayCurrency)).doubleValue

        var secondaryTotal: Double = 0.0
        if let secondaryCurrency = secondaryDisplayCurrencyProvider() {
            secondaryTotal = NSDecimalNumber(decimal: await newCoreTotalProvider(secondaryCurrency)).doubleValue
        }

        return FinanceTotalsSnapshot(
            totalAmount: total,
            secondaryTotalAmount: secondaryTotal,
            currencyConversionWarning: nil
        )
    }

    // MARK: - Public: Расчёт суммы по группе

    func calculateGroupTotal(group: FinanceGroup, in currency: String) async -> Double {
        var total: Double = 0.0
        let targetCurrency = normalizedConversionCurrency(currency)

        guard let accounts = group.accounts else { return 0.0 }

        for account in accounts {
            let amount = await getAccountAmount(account: account)
            let sourceCurrency = normalizedConversionCurrency(amount.currency)

            guard abs(amount.value) > 0.01 else { continue }

            if sourceCurrency == targetCurrency {
                total += amount.value
            } else {
                let rate = await currencyService.getRate(from: sourceCurrency, to: targetCurrency)
                if let rate = rate, rate > 0 {
                    total += amount.value * rate
                }
            }
        }

        return total
    }

    // MARK: - Public: Балансы всех счетов (для снапшотов)

    /// Возвращает текущий баланс каждого счёта из всех групп.
    /// Ключ — `account.accountID`. Используется в AccountBalanceSnapshotService.
    func calculateAllAccountBalances() async -> [String: (value: Double, currency: String)] {
        let groups = groupsProvider()
        var result: [String: (value: Double, currency: String)] = [:]
        for group in groups {
            guard let accounts = group.accounts else { continue }
            for account in accounts {
                let amount = await getAccountAmount(account: account)
                result[account.accountID] = amount
            }
        }
        return result
    }

    // MARK: - Public: Нормализация валюты

    func normalizedConversionCurrency(_ currency: String) -> String {
        let trimmed = currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard !trimmed.isEmpty else { return "USD" }

        let stablecoinToUSD: Set<String> = ["USDT", "USDC", "BUSD", "TUSD", "FDUSD", "DAI"]
        if stablecoinToUSD.contains(trimmed) {
            return "USD"
        }

        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/").map(String.init)
            if let quote = parts.last {
                return normalizedConversionCurrency(quote)
            }
        }

        if trimmed.contains("-") {
            let parts = trimmed.split(separator: "-").map(String.init)
            if let quote = parts.last {
                return normalizedConversionCurrency(quote)
            }
        }

        return trimmed
    }

    // MARK: - Public: Разрешение валюты инвестиции

    func resolvedInvestmentCurrency(_ investment: Investment, displayCurrency: String) -> String {
        let normalizedCurrency = investment.currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        if !normalizedCurrency.isEmpty {
            return normalizedCurrency
        }

        if let marketCurrency = investment.marketCurrency?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !marketCurrency.isEmpty {
            return marketCurrency
        }

        if let marketSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased(),
           !marketSymbol.isEmpty {
            if marketSymbol.contains("/") {
                let parts = marketSymbol.split(separator: "/").map(String.init)
                if let quote = parts.last, !quote.isEmpty {
                    return quote
                }
            }
            if marketSymbol.contains("-") {
                let parts = marketSymbol.split(separator: "-").map(String.init)
                if let quote = parts.last, !quote.isEmpty {
                    return quote
                }
            }
        }

        return displayCurrency
    }

    // MARK: - Private: Сумма счёта (per-group display легаси-мира)

    private func getAccountAmount(account: FinanceAccount) async -> (value: Double, currency: String) {
        // Дата всегда "сейчас" — TotalsService считает ТЕКУЩЕЕ состояние (per-group display Счетов),
        // в отличие от FinanceDynamicsViewModel, который умеет считать на произвольную дату.
        // Фильтр включения/знака — инлайн бывшего `AccountTotalPolicy` (снесён в 6b Фазе 2): архивные/
        // выключенные легаси-счета не должны "зависать" в per-group сумме. Легаси-мир read-only и
        // мигрирует в ядро — метод остаётся только для отображения групп до сноса легаси (Фаза 4/5).
        let now = Date()
        let displayCurrency = displayCurrencyProvider()
        switch account.accountType {
        case .card:
            if let card = cardByIDProvider()[account.accountID],
               Self.isActiveInTotal(includeInTotal: card.includeInTotal, archivedAt: card.archivedAt, at: now) {
                let snapshot = CardSnapshotFactory.make(from: card)
                return (snapshot.netWorthAmount, snapshot.currency)
            }

        case .credit:
            if let credit = creditByIDProvider()[account.accountID],
               Self.isActiveInTotal(includeInTotal: credit.includeInTotal, archivedAt: credit.archivedAt, at: now) {
                let value = Self.signedLiabilityContribution(credit.remainingAmount, isLiability: true, debtAsNegative: true)
                return (value, credit.currency)
            }

        case .investment:
            if let investment = investmentByIDProvider()[account.accountID],
               Self.isActiveInTotal(includeInTotal: investment.includeInTotal, archivedAt: investment.archivedAt, at: now) {
                let value = investment.investmentType == .positive ? investment.amount : -investment.amount
                return (value, resolvedInvestmentCurrency(investment, displayCurrency: displayCurrency))
            }
        }

        return (0.0, "RUB")
    }

    // MARK: - Private: Участие легаси-счёта (инлайн бывшего AccountTotalPolicy, снесён в 6b Фазе 2)

    /// Включён флагом И не архивирован строго до `date` (time-aware архивация).
    private static func isActiveInTotal(includeInTotal: Bool, archivedAt: Date?, at date: Date) -> Bool {
        guard includeInTotal else { return false }
        if let archivedAt, date > archivedAt { return false }
        return true
    }

    /// Знак обязательства (кредит/кредитка) для net-вклада; при `debtAsNegative == false` — как есть.
    private static func signedLiabilityContribution(_ amount: Double, isLiability: Bool, debtAsNegative: Bool) -> Double {
        guard debtAsNegative, isLiability else { return amount }
        return -abs(amount)
    }
}
