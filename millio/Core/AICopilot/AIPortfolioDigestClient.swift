//
//  AIPortfolioDigestClient.swift
//  millio
//

import Foundation

/// Формулировка дайджеста портфеля на сервере. Цифры считает приложение — клиент отдаёт готовый
/// payload и получает обратно только текст, статус и дисклеймер.
protocol AIPortfolioDigestClient: Sendable {
    var isAvailable: Bool { get }
    func digest(_ request: AIPortfolioDigestRequest) async throws -> AIPortfolioDigestResponse
}

/// Заглушка без DI-контейнера: экран показывает цифры и локальный дисклеймер, без спиннера.
struct UnavailableAIPortfolioDigestClient: AIPortfolioDigestClient {
    var isAvailable: Bool { false }

    func digest(_ request: AIPortfolioDigestRequest) async throws -> AIPortfolioDigestResponse {
        throw AICopilotClientError.unavailable
    }
}
