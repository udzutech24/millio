//
//  BackendAIPortfolioDigestClient.swift
//  millio
//

import Foundation

/// `POST /ai/portfolio-digest` через общий транспорт AI-эндпоинтов. Сервер отвечает 200 при любом
/// исходе модели — статус текста приходит полем `status`, а не HTTP-кодом.
final class BackendAIPortfolioDigestClient: AIPortfolioDigestClient, @unchecked Sendable {
    private let transport: AICopilotJSONTransport

    var isAvailable: Bool { true }

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared,
        maxResponseBytes: Int = 64 * 1_024
    ) {
        self.transport = AICopilotJSONTransport(
            authService: authService,
            configurationProvider: configurationProvider,
            session: session,
            maxResponseBytes: maxResponseBytes
        )
    }

    func digest(_ request: AIPortfolioDigestRequest) async throws -> AIPortfolioDigestResponse {
        try await transport.post(path: "ai/portfolio-digest", body: request)
    }
}
