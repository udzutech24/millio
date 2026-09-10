//
//  AIChatModels.swift
//  millio
//

import Foundation

/// Роль хода в диалоге. Значения совпадают с `ChatMessageDto.role` на бэкенде.
enum AIChatRole: String, Codable, Sendable {
    case user
    case assistant
}

/// Ход диалога, сохранённый на устройстве. Сервер stateless: историю храним и обрезаем здесь,
/// и она же служит памятью «этот вопрос уже спрашивали».
struct AIChatMessage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: AIChatRole
    let text: String
    let date: Date
    /// Подпись цифр, на которых был получен ответ (`AIPeriodSummaryPayloadBuilder.cacheKey`).
    /// Заполнена только у ответов модели: без неё повтор вопроса через месяц отдал бы
    /// прошлогодний ответ на новые цифры.
    let contextSignature: String?

    init(
        id: UUID = UUID(),
        role: AIChatRole,
        text: String,
        date: Date = Date(),
        contextSignature: String? = nil
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
        self.contextSignature = contextSignature
    }
}

/// Статус ответа. Бэкенд всегда отвечает `200`, реальное состояние лежит внутри тела.
enum AIChatStatus: String, Codable, Sendable {
    /// Текст есть.
    case ok
    /// Ответ ушёл в инвестиционные рекомендации: сервер оборвал его и прислал в `reply`
    /// локализованный отказ. Уже пришедшие предложения — начало отфильтрованного ответа.
    case filtered
    /// Модель не подключена — предлагать повтор бессмысленно.
    case unavailable
    /// Обрыв генерации или пустой ответ — повтор имеет смысл.
    case failed

    /// Незнакомый статус трактуем как сбой: молча показать пустоту хуже, чем предложить повтор.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AIChatStatus(rawValue: raw) ?? .failed
    }
}

// MARK: - Контракт с бэкендом

/// Тело `POST /ai/chat`.
///
/// ⚠️ На бэкенде `forbidNonWhitelisted` — любое лишнее поле возвращает 400. Набор ключей обязан
/// совпадать с `ChatRequestDto`, это проверяется тестом. Вложенные `Period`/`Totals`/`CategoryTotal`
/// намеренно переиспользованы из контракта итогов: на сервере это буквально те же DTO-классы.
struct AIChatRequest: Encodable, Equatable, Sendable {
    struct Message: Encodable, Equatable, Sendable {
        let role: String
        let text: String
    }

    /// Срез, на котором отвечает модель. `accounts` (опциональное поле DTO) сознательно не шлём:
    /// алиасы обезличены, назвать счёт в ответе всё равно нельзя, а балансы в разных валютах
    /// провоцируют модель их складывать — ровно то, что ей запрещено.
    struct Context: Encodable, Equatable, Sendable {
        let period: AIPeriodSummaryRequest.Period
        let currency: String
        let totals: AIPeriodSummaryRequest.Totals
        let byCategory: [AIPeriodSummaryRequest.CategoryTotal]
    }

    let schemaVersion: String
    let locale: String
    let question: String
    /// `nil` не попадает в JSON (синтезированный `encodeIfPresent`) — бэкенд ждёт отсутствие поля,
    /// а не `null`.
    let history: [Message]?
    let context: Context
}

/// Финальный объект ответа — одинаковый в JSON-режиме и в `event: done`.
struct AIChatReply: Decodable, Equatable, Sendable {
    let reply: String?
    let status: AIChatStatus

    init(reply: String?, status: AIChatStatus) {
        self.reply = reply
        self.status = status
    }

    private enum CodingKeys: String, CodingKey {
        case reply
        case status
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)
        status = (try container.decodeIfPresent(AIChatStatus.self, forKey: .status)) ?? .failed
    }
}

/// Событие потока: очередное целое предложение по мере генерации либо финал.
enum AIChatEvent: Equatable, Sendable {
    case delta(String)
    case done(AIChatReply)
}

enum AIChatClientError: Error, Equatable {
    case unavailable
    case unauthorized
    case rateLimited
    case transport
    case invalidContract
}
