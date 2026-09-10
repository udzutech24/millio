//
//  AIPortfolioDigestModels.swift
//  millio
//

import Foundation

/// Окно дайджеста портфеля.
enum AIPortfolioWindow: String, CaseIterable, Identifiable, Sendable {
    case month
    case quarter
    case year

    var id: String { rawValue }

    /// Скользящее окно, а не календарное: первого числа календарный месяц был бы пустым,
    /// и «движение за месяц» всегда выглядело бы нулевым.
    func start(from now: Date, calendar: Calendar = .current) -> Date {
        let months: Int = switch self {
        case .month: 1
        case .quarter: 3
        case .year: 12
        }
        return calendar.date(byAdding: .month, value: -months, to: now) ?? now
    }
}

/// Позиция в цифрах дайджеста. Всё посчитано на устройстве; модель эти числа только называет.
struct AIPortfolioPositionFigures: Equatable, Identifiable, Sendable {
    let accountID: UUID
    /// Имя счёта — только для экрана; в запрос не уходит (в контракте его нет).
    let name: String
    let symbol: String
    let assetClass: MarketAssetClass
    let value: Decimal
    let sharePercent: Decimal
    let changePercent: Decimal

    var id: UUID { accountID }
}

/// Цифры портфеля одной валюты за окно.
struct AIPortfolioFigures: Equatable, Sendable {
    let window: AIPortfolioWindow
    let currency: String
    let value: Decimal
    /// Изменение стоимости текущих позиций за счёт цен за окно — без покупок и продаж внутри окна.
    let changeAmount: Decimal
    let changePercent: Decimal
    /// По убыванию стоимости.
    let positions: [AIPortfolioPositionFigures]
    /// Валюты открытых позиций, не попавших в дайджест (без конвертации их не с чем складывать).
    let excludedCurrencies: [String]
}

// MARK: - Контракт с бэкендом

/// Тело `POST /ai/portfolio-digest`.
///
/// ⚠️ На бэкенде включён `forbidNonWhitelisted` — любое лишнее поле возвращает 400. Набор ключей
/// обязан совпадать с `PortfolioDigestRequestDto` один в один; это проверяется тестом.
struct AIPortfolioDigestRequest: Encodable, Equatable, Sendable {
    struct Totals: Encodable, Equatable, Sendable {
        let value: Double
        let changeAmount: Double
        let changePercent: Double
    }

    struct Position: Encodable, Equatable, Sendable {
        let symbol: String
        let assetClass: String
        let value: Double
        let sharePercent: Double
        let changePercent: Double
    }

    let schemaVersion: String
    let locale: String
    let currency: String
    let window: String
    let totals: Totals
    let positions: [Position]
}

/// `ok` — текст прошёл; `filtered` — сервер выбросил текст за директиву; `unavailable` — модели нет.
enum AIPortfolioDigestStatus: String, Decodable, Equatable, Sendable {
    case ok
    case filtered
    case unavailable

    /// Незнакомый статус трактуем как «текста нет»: показывать формулировку, которую клиент не
    /// умеет классифицировать, в инвест-разделе нельзя.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIPortfolioDigestStatus(rawValue: raw) ?? .unavailable
    }
}

enum AIPortfolioNoteKind: String, Decodable, Equatable, Sendable {
    case movement
    case structure
    case concentration

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIPortfolioNoteKind(rawValue: raw) ?? .structure
    }
}

struct AIPortfolioDigestNote: Decodable, Equatable, Identifiable, Sendable {
    let text: String
    let kind: AIPortfolioNoteKind
    let symbol: String?

    var id: String { "\(kind.rawValue)|\(symbol ?? "")|\(text)" }
}

/// Текст модели — отдельно от цифр: цифры на экране есть всегда, текст — только при `ok`.
struct AIPortfolioDigestText: Equatable, Sendable {
    let headline: String?
    let notes: [AIPortfolioDigestNote]

    var isEmpty: Bool { (headline?.isEmpty ?? true) && notes.isEmpty }
}

/// Ответ `POST /ai/portfolio-digest`. Эхо цифр (`window`/`currency`/`totals`) не читаем:
/// источник истины — устройство, из ответа берём только текст, дисклеймер и статус.
struct AIPortfolioDigestResponse: Decodable, Equatable, Sendable {
    let headline: String?
    let notes: [AIPortfolioDigestNote]
    let disclaimer: String?
    let status: AIPortfolioDigestStatus

    init(headline: String?, notes: [AIPortfolioDigestNote], disclaimer: String?, status: AIPortfolioDigestStatus) {
        self.headline = headline
        self.notes = notes
        self.disclaimer = disclaimer
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case headline
        case notes
        case disclaimer
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headline = try container.decodeIfPresent(String.self, forKey: .headline)
        notes = (try container.decodeIfPresent([AIPortfolioDigestNote].self, forKey: .notes)) ?? []
        disclaimer = try container.decodeIfPresent(String.self, forKey: .disclaimer)
        status = (try container.decodeIfPresent(AIPortfolioDigestStatus.self, forKey: .status)) ?? .unavailable
    }

    /// Формулировки — только при `ok`. `filtered` и `unavailable` показывают цифры без текста,
    /// даже если сервер по ошибке прислал заголовок или заметки.
    var text: AIPortfolioDigestText? {
        guard status == .ok else { return nil }
        let trimmedHeadline = headline?.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = AIPortfolioDigestText(
            headline: trimmedHeadline?.isEmpty == true ? nil : trimmedHeadline,
            notes: notes.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        )
        return result.isEmpty ? nil : result
    }
}
