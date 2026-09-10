//
//  AIPeriodSummaryPayloadBuilder.swift
//  millio
//

import Foundation

/// Цифры периода, посчитанные на устройстве. Сервер их не пересчитывает.
struct AIPeriodFigures: Equatable, Sendable {
    let income: Double
    let expense: Double
    let previousIncome: Double
    let previousExpense: Double
    let balanceEnd: Double

    var net: Double { income - expense }
    var previousNet: Double { previousIncome - previousExpense }

    static let zero = AIPeriodFigures(income: 0, expense: 0, previousIncome: 0, previousExpense: 0, balanceEnd: 0)
}

/// Сборка тела запроса итогов из уже готовых агрегатов. Чистая логика — новых расчётов денег здесь
/// нет, только окно дат и упаковка в контракт.
enum AIPeriodSummaryPayloadBuilder {
    static let schemaVersion = "1"

    /// Сколько категорий отправляем. Хвост из копеечных категорий модели ничего не добавляет,
    /// а payload раздувает.
    static let maxCategories = 12

    /// Суммы за диапазон. Окно то же, что у `CashflowInsightsChartBuilder.makePresentation`:
    /// от начала первого дня до конца последнего включительно — иначе цифры сводки разошлись бы
    /// с карточками на экране Кэшфлоу.
    static func totals(
        entries: [CashflowConvertedTransaction],
        in range: ClosedRange<Date>,
        calendar: Calendar = .current
    ) -> (income: Double, expense: Double) {
        let startDay = calendar.startOfDay(for: range.lowerBound)
        let endDay = calendar.startOfDay(for: range.upperBound)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        var income: Double = 0
        var expense: Double = 0
        for entry in entries where entry.date >= startDay && entry.date < endExclusive {
            income += entry.income
            expense += entry.expense
        }
        return (income, expense)
    }

    static func figures(
        entries: [CashflowConvertedTransaction],
        period: AIPeriodSummaryPeriod,
        now: Date,
        balanceEnd: Double,
        calendar: Calendar = .current
    ) -> AIPeriodFigures {
        let current = totals(entries: entries, in: period.effectiveRange(now: now, calendar: calendar), calendar: calendar)
        let previous = totals(entries: entries, in: period.previousRange(now: now, calendar: calendar), calendar: calendar)
        return AIPeriodFigures(
            income: current.income,
            expense: current.expense,
            previousIncome: previous.income,
            previousExpense: previous.expense,
            balanceEnd: balanceEnd
        )
    }

    /// Бэкенд принимает только ru / en / zh-Hans, а приложение локализовано шире —
    /// всё остальное сводим к английскому, иначе строгий DTO вернёт 400.
    static func backendLocale(from locale: Locale) -> String {
        let language = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        if language.hasPrefix("ru") { return "ru" }
        if language.hasPrefix("zh") { return "zh-Hans" }
        return "en"
    }

    static func makeRequest(
        period: AIPeriodSummaryPeriod,
        now: Date,
        figures: AIPeriodFigures,
        categoryTotals: [String: Double],
        currency: String,
        locale: Locale,
        calendar: Calendar = .current
    ) -> AIPeriodSummaryRequest {
        let range = period.effectiveRange(now: now, calendar: calendar)
        let byCategory = categoryTotalsPayload(categoryTotals)

        return AIPeriodSummaryRequest(
            schemaVersion: schemaVersion,
            locale: backendLocale(from: locale),
            period: AIPeriodSummaryRequest.Period(
                kind: period.kind.rawValue,
                start: dayString(range.lowerBound, calendar: calendar),
                end: dayString(range.upperBound, calendar: calendar)
            ),
            currency: currency,
            totals: AIPeriodSummaryRequest.Totals(
                income: round2(figures.income),
                expense: round2(figures.expense),
                net: round2(figures.net),
                balanceEnd: round2(figures.balanceEnd)
            ),
            byCategory: byCategory,
            previousPeriod: AIPeriodSummaryRequest.PreviousPeriod(
                income: round2(figures.previousIncome),
                expense: round2(figures.previousExpense),
                net: round2(figures.previousNet)
            )
        )
    }

    /// Разбивка по категориям в контракт: нули отбрасываем, сортируем по убыванию суммы и режем
    /// хвост. Общая для итогов и чата — на бэкенде это один и тот же `PeriodSummaryCategoryTotalDto`.
    static func categoryTotalsPayload(_ categoryTotals: [String: Double]) -> [AIPeriodSummaryRequest.CategoryTotal] {
        categoryTotals
            .filter { $0.value.rounded() != 0 }
            .sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }
            .prefix(maxCategories)
            .map { AIPeriodSummaryRequest.CategoryTotal(categoryId: String($0.key.prefix(128)), amount: round2($0.value)) }
    }

    /// Ключ кэша «период + цифры». Разбивку по категориям в ключ НЕ берём намеренно: она считается
    /// асинхронно с конвертацией каждой транзакции, а попадание в кэш обязано быть мгновенным и
    /// вообще не запускать эту работу.
    static func cacheKey(
        period: AIPeriodSummaryPeriod,
        now: Date,
        figures: AIPeriodFigures,
        currency: String,
        locale: Locale,
        calendar: Calendar = .current
    ) -> String {
        let range = period.effectiveRange(now: now, calendar: calendar)
        let parts: [String] = [
            schemaVersion,
            backendLocale(from: locale),
            currency,
            period.kind.rawValue,
            dayString(range.lowerBound, calendar: calendar),
            dayString(range.upperBound, calendar: calendar),
            money(figures.income),
            money(figures.expense),
            money(figures.net),
            money(figures.balanceEnd),
            money(figures.previousIncome),
            money(figures.previousExpense)
        ]
        return parts.joined(separator: "|")
    }

    // MARK: - Helpers

    static func dayString(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func round2(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }

    private static func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
