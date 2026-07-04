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
    /// Вклад нового ядра event-sourcing (Фаза 1a-ui, AC2) — `AccountsTotalsService.totalAt(date, in:)`,
    /// та же функция, что использует Analytics-тотал (`FinanceDynamicsViewModel.calculateTotalForAllGroups`),
    /// поэтому Accounts-тотал и Analytics-тотал совпадают до копейки по построению, а не по совпадению.
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

    func calculateTotalsSnapshot() async -> FinanceTotalsSnapshot {
        let displayCurrency = displayCurrencyProvider()
        let groups = groupsProvider()
        var total: Double = 0.0
        var warnings: Set<String> = []

        // Собираем все валюты из всех групп
        var allCurrenciesNeeded = Set<String>()
        for group in groups {
            let currencies = await collectCurrenciesFromGroup(group: group)
            allCurrenciesNeeded.formUnion(currencies)
            let groupCurrency = group.displayCurrency ?? displayCurrency
            allCurrenciesNeeded.insert(groupCurrency)
        }
        allCurrenciesNeeded.insert(displayCurrency)
        if let secondaryCurrency = secondaryDisplayCurrencyProvider() {
            allCurrenciesNeeded.insert(secondaryCurrency)
        }

        // Рассчитываем основную сумму
        for group in groups {
            let groupCurrency = group.displayCurrency ?? displayCurrency
            let groupTotalInGroupCurrency = await calculateGroupTotal(group: group, in: groupCurrency)
            let normalizedGroupCurrency = normalizedConversionCurrency(groupCurrency)
            let normalizedDisplayCurrency = normalizedConversionCurrency(displayCurrency)

            if normalizedGroupCurrency == normalizedDisplayCurrency {
                total += groupTotalInGroupCurrency
            } else {
                if let rate = await currencyService.getRate(from: normalizedGroupCurrency, to: normalizedDisplayCurrency), rate > 0 {
                    total += groupTotalInGroupCurrency * rate
                } else {
                    warnings.insert(FinancesL10n.format("finances.warning.rate_unavailable", groupCurrency, displayCurrency))
                    AppLogger.log(
                        .warning,
                        category: "Finance",
                        "[Conversion] Failed to convert group amount \"\(group.name)\" from \(groupCurrency) to \(displayCurrency). Amount ignored."
                    )
                }
            }
        }

        // Рассчитываем дополнительную сумму
        var secondaryTotal: Double = 0.0
        if let secondaryCurrency = secondaryDisplayCurrencyProvider() {
            for group in groups {
                let groupCurrency = group.displayCurrency ?? displayCurrency
                let groupTotalInGroupCurrency = await calculateGroupTotal(group: group, in: groupCurrency)
                let normalizedGroupCurrency = normalizedConversionCurrency(groupCurrency)
                let normalizedSecondaryCurrency = normalizedConversionCurrency(secondaryCurrency)

                if normalizedGroupCurrency == normalizedSecondaryCurrency {
                    secondaryTotal += groupTotalInGroupCurrency
                } else {
                    if let rate = await currencyService.getRate(from: normalizedGroupCurrency, to: normalizedSecondaryCurrency), rate > 0 {
                        secondaryTotal += groupTotalInGroupCurrency * rate
                    } else {
                        warnings.insert(FinancesL10n.format("finances.warning.rate_unavailable", groupCurrency, secondaryCurrency))
                        AppLogger.log(
                            .warning,
                            category: "Finance",
                            "[Conversion] Failed to convert group amount \"\(group.name)\" from \(groupCurrency) to \(secondaryCurrency). Amount ignored."
                        )
                    }
                }
            }
        }

        // Вклад нового ядра (AC2) — добавляется В ТУ ЖЕ сумму, поверх старого мира, единой функцией.
        let newCoreTotal = NSDecimalNumber(decimal: await newCoreTotalProvider(displayCurrency)).doubleValue
        total += newCoreTotal
        if let secondaryCurrency = secondaryDisplayCurrencyProvider() {
            secondaryTotal += NSDecimalNumber(decimal: await newCoreTotalProvider(secondaryCurrency)).doubleValue
        }

        return FinanceTotalsSnapshot(
            totalAmount: total,
            secondaryTotalAmount: secondaryTotal,
            currencyConversionWarning: warnings.isEmpty ? nil : warnings.sorted().joined(separator: "\n")
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

    // MARK: - Private: Сбор валют группы

    private func collectCurrenciesFromGroup(group: FinanceGroup) async -> Set<String> {
        var currencies: Set<String> = []
        guard let accounts = group.accounts else { return currencies }

        for account in accounts {
            let amount = await getAccountAmount(account: account)
            if abs(amount.value) > 0.01 {
                currencies.insert(normalizedConversionCurrency(amount.currency))
            }
        }

        return currencies
    }

    // MARK: - Private: Сумма счёта

    private func getAccountAmount(account: FinanceAccount) async -> (value: Double, currency: String) {
        let displayCurrency = displayCurrencyProvider()
        switch account.accountType {
        case .card:
            if let card = cardByIDProvider()[account.accountID] {
                let snapshot = CardSnapshotFactory.make(from: card)
                return (snapshot.netWorthAmount, snapshot.currency)
            }

        case .credit:
            if let credit = creditByIDProvider()[account.accountID] {
                return (-credit.remainingAmount, credit.currency)
            }

        case .investment:
            if let investment = investmentByIDProvider()[account.accountID] {
                if investment.includeInTotal {
                    let value = investment.investmentType == .positive ? investment.amount : -investment.amount
                    return (value, resolvedInvestmentCurrency(investment, displayCurrency: displayCurrency))
                }
            }
        }

        return (0.0, "RUB")
    }
}
