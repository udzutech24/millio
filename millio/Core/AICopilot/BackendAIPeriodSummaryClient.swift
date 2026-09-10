//
//  BackendAIPeriodSummaryClient.swift
//  millio
//

import Foundation

/// `POST /ai/period-summary` через общий транспорт AI-эндпоинтов (Bearer + один повтор при 401).
final class BackendAIPeriodSummaryClient: AIPeriodSummaryClient, @unchecked Sendable {
    private let transport: AICopilotJSONTransport

    var isAvailable: Bool { true }

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared,
        maxResponseBytes: Int = 256 * 1_024
    ) {
        self.transport = AICopilotJSONTransport(
            authService: authService,
            configurationProvider: configurationProvider,
            session: session,
            maxResponseBytes: maxResponseBytes
        )
    }

    func summarize(_ request: AIPeriodSummaryRequest) async throws -> AIPeriodSummaryText {
        try await transport.post(path: "ai/period-summary", body: request)
    }
}
