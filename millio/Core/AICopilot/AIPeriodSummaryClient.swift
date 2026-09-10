//
//  AIPeriodSummaryClient.swift
//  millio
//

import Foundation

/// Формулировка итогов периода на сервере. Цифры считает приложение — клиент отдаёт готовый payload
/// и получает обратно только текст.
protocol AIPeriodSummaryClient: Sendable {
    var isAvailable: Bool { get }
    func summarize(_ request: AIPeriodSummaryRequest) async throws -> AIPeriodSummaryText
}

enum AIPeriodSummaryClientError: Error, Equatable {
    case unavailable
    case unauthorized
    case rateLimited
    case transport
    case invalidContract
}

/// Заглушка на случай, когда DI-контейнера ещё нет: экран обязан показать цифры без текста,
/// а не пустоту и не спиннер (образец — `UnavailableCashflowStatementImportClient`).
struct UnavailableAIPeriodSummaryClient: AIPeriodSummaryClient {
    var isAvailable: Bool { false }

    func summarize(_ request: AIPeriodSummaryRequest) async throws -> AIPeriodSummaryText {
        throw AIPeriodSummaryClientError.unavailable
    }
}
