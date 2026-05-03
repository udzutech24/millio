//
//  CashflowCurrencyService.swift
//  millio
//
//  Сервис конвертации валют для транзакций cashflow.
//  Выделен из CashflowViewModel (Phase 2 декомпозиции).
//

import Foundation
import SwiftData

// MARK: - CashflowCurrencyService

@MainActor
final class CashflowCurrencyService {

    // MARK: - Dependencies

    private let historicalRateStore: HistoricalRateStore
    private let now: () -> Date
    /// Возвращает Card по cardID (ищет в кэше или через modelContext).
    private let cardResolver: (String) -> Card?
    /// Возвращает текущую отображаемую валюту из state.
    private let displayCurrencyProvider: () -> String
    /// Вызывается при получении приблизительного курса (мутирует state через ViewModel).
    let onEstimatedRateWarning: (Date) -> Void

    // MARK: - Init

    init(
        historicalRateStore: HistoricalRateStore,
        now: @escaping () -> Date,
        cardResolver: @escaping (String) -> Card?,
        displayCurrencyProvider: @escaping () -> String,
        onEstimatedRateWarning: @escaping (Date) -> Void
    ) {
        self.historicalRateStore = historicalRateStore
        self.now = now
        self.cardResolver = cardResolver
        self.displayCurrencyProvider = displayCurrencyProvider
        self.onEstimatedRateWarning = onEstimatedRateWarning
    }

    // MARK: - Public API

    /// Конвертирует сумму транзакции в целевую валюту.
    func convertAmountForTransaction(_ transaction: CashflowTransaction, to currency: String) async -> Double {
        if transaction.currency == currency {
            return transaction.amount
        }

        if let rate = transaction.exchangeRate,
           let rateCurrency = transaction.exchangeRateCurrency,
           rateCurrency == currency {
            return transaction.amount * rate
        }

        let result = await historicalRateStore.getRate(
            on: transaction.transactionDate,
            from: transaction.currency,
            to: currency
        )

        if result.resolution != .exact {
            onEstimatedRateWarning(result.rateDate ?? transaction.transactionDate)
        }

        if let rate = result.rate {
            return transaction.amount * rate
        }

        if let converted = await CurrencyRateService.shared.convert(
            amount: transaction.amount,
            from: transaction.currency,
            to: currency
        ) {
            onEstimatedRateWarning(now())
            return converted
        }

        return transaction.amount
    }

    /// Простая конвертация суммы без привязки к транзакции.
    func convertAmount(value: Double, from: String, to: String) async -> Double {
        if from == to {
            return value
        }

        if let converted = await CurrencyRateService.shared.convert(
            amount: value,
            from: from,
            to: to
        ) {
            return converted
        }

        return value
    }

    /// Конвертация с проверкой доступности: использует исторический курс, fallback — live.
    func convertAmountForValidation(amount: Double, from: String, to: String, on date: Date) async throws -> Double {
        if from == to {
            return amount
        }

        let result = await historicalRateStore.getRate(on: date, from: from, to: to)
        if let rate = result.rate {
            return amount * rate
        }

        if let converted = await CurrencyRateService.shared.convert(
            amount: amount,
            from: from,
            to: to
        ) {
            return converted
        }

        AppLogger.log(
            .error,
            category: "Cashflow",
            "Currency conversion failed: from=\(from) to=\(to) date=\(date), no rate from historical store or rate service"
        )
        throw ConversionError.rateUnavailable(from: from, to: to, date: date)
    }

    /// Возвращает ExchangeInfo для транзакции (трансфер или обычная транзакция).
    func resolveExchangeInfo(for transaction: CashflowTransaction) async -> CashflowExchangeInfo {
        if transaction.transactionType == .transfer,
           let targetCurrency = normalizedCurrencyCode(cardResolver(transaction.toCardID ?? "")?.currency) {
            let sourceCurrency = normalizedCurrencyCode(transaction.currency) ?? targetCurrency
            let rateDate = Calendar.current.startOfDay(for: transaction.transactionDate)

            if sourceCurrency == targetCurrency {
                return CashflowExchangeInfo(rate: 1.0, rateDate: rateDate, rateCurrency: targetCurrency)
            }

            if let explicitRate = transaction.exchangeRate,
               explicitRate > 0,
               normalizedCurrencyCode(transaction.exchangeRateCurrency) == targetCurrency {
                return CashflowExchangeInfo(
                    rate: explicitRate,
                    rateDate: transaction.exchangeRateDate ?? rateDate,
                    rateCurrency: targetCurrency
                )
            }

            let result = await historicalRateStore.getRate(
                on: transaction.transactionDate,
                from: sourceCurrency,
                to: targetCurrency
            )

            return CashflowExchangeInfo(
                rate: result.rate,
                rateDate: result.rateDate ?? rateDate,
                rateCurrency: result.rate != nil ? targetCurrency : nil
            )
        }

        let targetCurrency = displayCurrencyProvider()

        guard transaction.currency != targetCurrency else {
            return CashflowExchangeInfo(
                rate: 1.0,
                rateDate: Calendar.current.startOfDay(for: transaction.transactionDate),
                rateCurrency: targetCurrency
            )
        }

        let result = await historicalRateStore.getRate(
            on: transaction.transactionDate,
            from: transaction.currency,
            to: targetCurrency
        )

        return CashflowExchangeInfo(
            rate: result.rate,
            rateDate: result.rateDate,
            rateCurrency: result.rate != nil ? targetCurrency : nil
        )
    }

    /// Предлагает курс обмена для нового трансфера на заданную дату.
    func suggestedTransferExchangeInfo(
        from sourceCurrency: String,
        to targetCurrency: String,
        on date: Date
    ) async -> TransferExchangeSuggestion? {
        let source = normalizedCurrencyCode(sourceCurrency) ?? sourceCurrency
        let target = normalizedCurrencyCode(targetCurrency) ?? targetCurrency
        let normalizedDate = Calendar.current.startOfDay(for: date)
        let today = Calendar.current.startOfDay(for: now())

        guard source != target else {
            return TransferExchangeSuggestion(rate: 1.0, rateDate: normalizedDate, isLiveRate: false)
        }

        let shouldPreferHistorical = normalizedDate < today

        func makeHistoricalSuggestion() async -> TransferExchangeSuggestion? {
            let historical = await historicalRateStore.getRate(
                on: date,
                from: source,
                to: target
            )
            guard let rate = historical.rate, rate > 0 else { return nil }
            return TransferExchangeSuggestion(
                rate: rate,
                rateDate: historical.rateDate ?? normalizedDate,
                isLiveRate: false
            )
        }

        if shouldPreferHistorical, let historicalSuggestion = await makeHistoricalSuggestion() {
            return historicalSuggestion
        }

        if let liveRate = await CurrencyRateService.shared.convert(
            amount: 1,
            from: source,
            to: target
        ), liveRate > 0 {
            return TransferExchangeSuggestion(
                rate: liveRate,
                rateDate: today,
                isLiveRate: true
            )
        }

        return await makeHistoricalSuggestion()
    }

    /// Считает сумму, которую получит карточка-получатель при трансфере.
    func transferReceivedAmount(
        for transaction: CashflowTransaction,
        in cardCurrency: String
    ) async throws -> Double {
        if let rate = transaction.exchangeRate,
           rate > 0,
           normalizedCurrencyCode(transaction.exchangeRateCurrency) == normalizedCurrencyCode(cardCurrency) {
            return transaction.amount * rate
        }

        return try await convertAmountForValidation(
            amount: transaction.amount,
            from: transaction.currency,
            to: cardCurrency,
            on: transaction.transactionDate
        )
    }

    // MARK: - Static Helpers

    /// Текст предупреждения об приблизительном курсе.
    static func estimatedRateWarningText(
        asOf date: Date,
        locale: Locale = AppLocalization.currentAppLocale
    ) -> String {
        let base = AppLocalization.string("finances.dynamics.warning.estimated_rate", locale: locale)
        let baseWithoutTrailingDot = base
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))

        let formatter = DateFormatter()
        formatter.locale = locale
        let template = LocalizationSupport.effectiveLanguage(for: locale) == Language.english.rawValue
            ? "Mdyyyy"
            : "dMMyyyy"
        formatter.setLocalizedDateFormatFromTemplate(template)
        let dateText = formatter.string(from: date)
        let suffixFormat = AppLocalization.string(
            "finances.dynamics.warning.estimated_rate.as_of",
            locale: locale,
            fallback: "as of %@"
        )
        return "\(baseWithoutTrailingDot) \(String(format: suffixFormat, locale: locale, dateText))"
    }

    // MARK: - Internal Helpers

    func normalizedCurrencyCode(_ currency: String?) -> String? {
        guard let currency else { return nil }
        let normalized = currency
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

// MARK: - CashflowExchangeInfo

/// Публичный аналог приватного ExchangeInfo из ViewModel.
struct CashflowExchangeInfo {
    let rate: Double?
    let rateDate: Date?
    let rateCurrency: String?
}
