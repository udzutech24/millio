//
//  AIChatPayloadBuilder.swift
//  millio
//

import Foundation

/// Срез, на котором чат отвечает: те же цифры, что видит владелец на экране итогов.
/// Свои расчёты денег здесь запрещены — снапшот приходит готовым.
struct AIChatContextSnapshot: Equatable, Sendable {
    let period: AIPeriodSummaryPeriod
    let figures: AIPeriodFigures
    let currency: String
    /// Расходы по категориям, ключ — отображаемое имя (модель пишет на языке владельца).
    let categoryTotals: [String: Double]

    static let empty = AIChatContextSnapshot(
        period: AIPeriodSummaryPeriod(kind: .month, anchor: Date(timeIntervalSince1970: 0)),
        figures: .zero,
        currency: "RUB",
        categoryTotals: [:]
    )
}

/// Сборка тела `POST /ai/chat`. Чистая логика: обрезки, нормализация и упаковка в контракт.
enum AIChatPayloadBuilder {
    static let schemaVersion = "1"

    /// Границы бэкенда (`ChatRequestDto`): вопрос ≤1000, история ≤20 ходов, текст хода ≤4000.
    /// Режем на клиенте — иначе строгая валидация вернёт 400 вместо ответа.
    static let maxQuestionLength = 1_000
    static let maxHistoryMessages = 20
    static let maxMessageLength = 4_000

    static func normalizedQuestion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > maxQuestionLength else { return trimmed }
        return String(trimmed.prefix(maxQuestionLength))
    }

    /// Последние ходы диалога. Именно последние: обрезать начало дешевле для смысла, чем конец —
    /// модель отвечает на актуальный контекст беседы.
    static func trimmedHistory(_ messages: [AIChatMessage]) -> [AIChatRequest.Message] {
        messages
            .suffix(maxHistoryMessages)
            .map {
                AIChatRequest.Message(
                    role: $0.role.rawValue,
                    text: String($0.text.prefix(maxMessageLength))
                )
            }
    }

    static func makeRequest(
        question: String,
        history: [AIChatMessage],
        snapshot: AIChatContextSnapshot,
        locale: Locale,
        now: Date,
        calendar: Calendar = .current
    ) -> AIChatRequest {
        let range = snapshot.period.effectiveRange(now: now, calendar: calendar)
        let trimmed = trimmedHistory(history)

        return AIChatRequest(
            schemaVersion: schemaVersion,
            locale: AIPeriodSummaryPayloadBuilder.backendLocale(from: locale),
            question: normalizedQuestion(question),
            history: trimmed.isEmpty ? nil : trimmed,
            context: AIChatRequest.Context(
                period: AIPeriodSummaryRequest.Period(
                    kind: snapshot.period.kind.rawValue,
                    start: AIPeriodSummaryPayloadBuilder.dayString(range.lowerBound, calendar: calendar),
                    end: AIPeriodSummaryPayloadBuilder.dayString(range.upperBound, calendar: calendar)
                ),
                currency: snapshot.currency,
                totals: AIPeriodSummaryRequest.Totals(
                    income: AIPeriodSummaryPayloadBuilder.round2(snapshot.figures.income),
                    expense: AIPeriodSummaryPayloadBuilder.round2(snapshot.figures.expense),
                    net: AIPeriodSummaryPayloadBuilder.round2(snapshot.figures.net),
                    balanceEnd: AIPeriodSummaryPayloadBuilder.round2(snapshot.figures.balanceEnd)
                ),
                byCategory: AIPeriodSummaryPayloadBuilder.categoryTotalsPayload(snapshot.categoryTotals)
            )
        )
    }

    /// Подпись цифр среза. Тот же ключ, что у кэша итогов: одинаковые цифры — одинаковый ответ,
    /// изменились — прошлый ответ переиспользовать нельзя.
    static func contextSignature(
        snapshot: AIChatContextSnapshot,
        locale: Locale,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        AIPeriodSummaryPayloadBuilder.cacheKey(
            period: snapshot.period,
            now: now,
            figures: snapshot.figures,
            currency: snapshot.currency,
            locale: locale,
            calendar: calendar
        )
    }

    /// Ключ поиска повтора: регистр и лишние пробелы не должны заставлять платить за тот же ответ.
    static func questionKey(_ raw: String) -> String {
        normalizedQuestion(raw)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
