//
//  FinanceSavingsGoalService.swift
//  millio
//
//  Сервис управления целью накоплений в Finance.
//  Выделен из FinanceViewModel (Phase 3 декомпозиции).
//

import Foundation

// MARK: - FinanceSavingsGoalService

/// Инкапсулирует хранение и конвертацию цели накоплений.
/// ViewModel передаёт текущие значения и получает обновлённые через результат.
@MainActor
final class FinanceSavingsGoalService {

    // MARK: - Keys

    private enum Key {
        static let enabled = "finance_savings_goal_enabled"
        static let amount = "finance_savings_goal_amount"
        static let currency = "finance_savings_goal_currency"
    }

    // MARK: - Dependencies

    private let defaults: UserDefaults
    private let currencyRateService: CurrencyRateServiceProtocol

    // MARK: - Init

    init(
        defaults: UserDefaults = .standard,
        currencyRateService: CurrencyRateServiceProtocol
    ) {
        self.defaults = defaults
        self.currencyRateService = currencyRateService
    }

    // MARK: - Persistent Storage

    var storedEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var storedAmount: Double {
        get { defaults.double(forKey: Key.amount) }
        set { defaults.set(newValue, forKey: Key.amount) }
    }

    var storedCurrency: String {
        get {
            let value = defaults.string(forKey: Key.currency)
            let normalized = Self.normalizedConversionCurrency(value ?? "")
            return normalized.isEmpty ? "USD" : normalized
        }
        set {
            let normalized = Self.normalizedConversionCurrency(newValue)
            defaults.set(normalized.isEmpty ? "USD" : normalized, forKey: Key.currency)
        }
    }

    // MARK: - Set Enabled

    /// Обновляет флаг включённости цели и сохраняет в defaults.
    func setEnabled(_ enabled: Bool) {
        storedEnabled = enabled
    }

    // MARK: - Set Amount

    /// Обновляет сумму цели и сохраняет валюту в defaults.
    /// - Returns: Сохранённая сумма (без изменений).
    func setAmount(_ amount: Double, currency: String) {
        storedAmount = amount
        storedCurrency = currency
    }

    // MARK: - Conversion

    /// Результат конвертации цели.
    struct ConversionResult {
        let newAmount: Double
        let newCurrency: String
    }

    /// Конвертирует цель накоплений из одной валюты в другую (если нужно).
    /// - Returns: `ConversionResult` при успешной конвертации, `nil` — если конвертация не требуется или не удалась.
    func convertIfNeeded(
        currentAmount: Double,
        from sourceCurrency: String,
        to targetCurrency: String
    ) async -> ConversionResult? {
        let source = Self.normalizedConversionCurrency(sourceCurrency)
        let target = Self.normalizedConversionCurrency(targetCurrency)

        guard !source.isEmpty, !target.isEmpty else { return nil }

        guard currentAmount > 0 else {
            storedCurrency = targetCurrency
            return ConversionResult(newAmount: currentAmount, newCurrency: targetCurrency)
        }

        guard source != target else {
            storedCurrency = targetCurrency
            return ConversionResult(newAmount: currentAmount, newCurrency: targetCurrency)
        }

        guard let rate = await currencyRateService.getRate(from: source, to: target), rate > 0 else {
            AppLogger.log(
                .warning,
                category: "Finance",
                "Failed to convert savings goal amount from \(sourceCurrency) to \(targetCurrency): rate unavailable"
            )
            return nil
        }

        let convertedAmount = currentAmount * rate
        guard convertedAmount.isFinite, convertedAmount > 0 else { return nil }

        let roundedAmount = max(1.0, convertedAmount.rounded())
        storedAmount = roundedAmount
        storedCurrency = targetCurrency

        return ConversionResult(newAmount: roundedAmount, newCurrency: targetCurrency)
    }

    // MARK: - Static Helpers

    /// Нормализует код валюты для конвертации.
    /// Стейблкоины → USD, пары через `/` или `-` → quote-currency.
    static func normalizedConversionCurrency(_ currency: String) -> String {
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
}
