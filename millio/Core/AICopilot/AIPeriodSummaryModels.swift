//
//  AIPeriodSummaryModels.swift
//  millio
//

import Foundation

/// Период итогов AI-сводки.
///
/// Намеренно ЛОКАЛЬНЫЙ тип, а не новый кейс в `CashflowInsightsGranularity` (year/month/week):
/// та гранулярность задаёт ось всех графиков кэшфлоу и разобрана десятками `switch` — квартал,
/// добавленный туда, разошёлся бы по всему модулю ради одного экрана.
enum AIPeriodKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case month
    case quarter

    var id: String { rawValue }
}

/// Границы периода итогов. Все цифры считаются на устройстве; сервер только формулирует текст.
struct AIPeriodSummaryPeriod: Equatable, Sendable {
    let kind: AIPeriodKind
    /// Любая дата внутри периода — начало вычисляется от неё.
    let anchor: Date

    static func current(kind: AIPeriodKind, now: Date) -> AIPeriodSummaryPeriod {
        AIPeriodSummaryPeriod(kind: kind, anchor: now)
    }

    func start(calendar: Calendar = .current) -> Date {
        switch kind {
        case .month:
            let components = calendar.dateComponents([.year, .month], from: anchor)
            return calendar.startOfDay(for: calendar.date(from: components) ?? anchor)
        case .quarter:
            let month = calendar.component(.month, from: anchor)
            let year = calendar.component(.year, from: anchor)
            let startMonth = ((month - 1) / 3) * 3 + 1
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? anchor
            return calendar.startOfDay(for: start)
        }
    }

    /// Последний календарный день периода — без оглядки на «сегодня».
    func calendarEnd(calendar: Calendar = .current) -> Date {
        let start = start(calendar: calendar)
        let monthSpan = kind == .month ? 1 : 3
        let end = calendar.date(byAdding: DateComponents(month: monthSpan, day: -1), to: start) ?? start
        return calendar.startOfDay(for: end)
    }

    /// Диапазон, за который реально считаем итоги: конец обрезан сегодняшним днём.
    /// Так итоги за текущий месяц совпадают с экраном Кэшфлоу — `CashflowAnalyticsService.getDateRange`
    /// для `.month` тоже клампит конец до `today`, а будущие дни всё равно пусты.
    func effectiveRange(now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let start = start(calendar: calendar)
        let today = calendar.startOfDay(for: now)
        let end = min(calendarEnd(calendar: calendar), today)
        return start...max(start, end)
    }

    /// Отрезок той же длины непосредственно перед текущим — ровно та же арифметика, что в
    /// `CashflowInsightsChartBuilder.makePresentation` для карточек сравнения. Календарный
    /// предыдущий месяц здесь был бы хуже: незакрытый текущий месяц сравнивался бы с полным
    /// прошлым, и модель называла бы падением обычную неполноту периода.
    func previousRange(now: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let current = effectiveRange(now: now, calendar: calendar)
        let dayCount = max(
            (calendar.dateComponents([.day], from: current.lowerBound, to: current.upperBound).day ?? 0) + 1,
            1
        )
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: current.lowerBound) ?? current.lowerBound
        let previousStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: previousEnd) ?? previousEnd
        return previousStart...max(previousStart, previousEnd)
    }

    /// Календарные месяцы, попадающие в период: 1 для месяца, 3 для квартала.
    func months(calendar: Calendar = .current) -> [Date] {
        let start = start(calendar: calendar)
        let count = kind == .month ? 1 : 3
        return (0..<count).compactMap { calendar.date(byAdding: .month, value: $0, to: start) }
    }
}

// MARK: - Контракт с бэкендом

/// Тело `POST /ai/period-summary`.
///
/// ⚠️ На бэкенде включён `forbidNonWhitelisted` — любое лишнее поле возвращает 400. Набор ключей
/// здесь обязан совпадать с `PeriodSummaryRequestDto` один в один; это проверяется тестом.
struct AIPeriodSummaryRequest: Encodable, Equatable, Sendable {
    struct Period: Encodable, Equatable, Sendable {
        let kind: String
        let start: String
        let end: String
    }

    struct Totals: Encodable, Equatable, Sendable {
        let income: Double
        let expense: Double
        let net: Double
        let balanceEnd: Double
    }

    struct CategoryTotal: Encodable, Equatable, Sendable {
        let categoryId: String
        let amount: Double
    }

    struct PreviousPeriod: Encodable, Equatable, Sendable {
        let income: Double
        let expense: Double
        let net: Double
    }

    let schemaVersion: String
    let locale: String
    let period: Period
    let currency: String
    let totals: Totals
    let byCategory: [CategoryTotal]
    let previousPeriod: PreviousPeriod
}

enum AIObservationKind: String, Codable, Sendable {
    case growth
    case drop
    case steady

    /// Незнакомый вид наблюдения не должен ронять весь ответ — деградируем в нейтральный.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIObservationKind(rawValue: raw) ?? .steady
    }
}

struct AIPeriodObservation: Codable, Equatable, Identifiable, Sendable {
    let text: String
    let kind: AIObservationKind

    var id: String { "\(kind.rawValue)|\(text)" }
}

/// Текстовая часть ответа. Цифры сервер только эхо-подтверждает — их источник истины на устройстве,
/// поэтому из ответа мы читаем исключительно формулировки.
struct AIPeriodSummaryText: Codable, Equatable, Sendable {
    let headline: String?
    let observations: [AIPeriodObservation]

    var isEmpty: Bool { (headline?.isEmpty ?? true) && observations.isEmpty }

    init(headline: String?, observations: [AIPeriodObservation]) {
        self.headline = headline
        self.observations = observations
    }

    private enum CodingKeys: String, CodingKey {
        case headline
        case observations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawHeadline = try container.decodeIfPresent(String.self, forKey: .headline)
        headline = rawHeadline?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : rawHeadline
        observations = (try container.decodeIfPresent([AIPeriodObservation].self, forKey: .observations)) ?? []
    }
}
