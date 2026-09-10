//
//  BackendAIPeriodSummaryClient.swift
//  millio
//

import Foundation

/// `POST /ai/period-summary` с Bearer-токеном и одним повтором при 401 —
/// по образцу `BackendCashflowStatementImportClient`.
final class BackendAIPeriodSummaryClient: AIPeriodSummaryClient, @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let session: URLSession
    private let maxResponseBytes: Int

    var isAvailable: Bool { true }

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared,
        maxResponseBytes: Int = 256 * 1_024
    ) {
        self.authService = authService
        self.configurationProvider = configurationProvider
        self.session = session
        self.maxResponseBytes = maxResponseBytes
    }

    func summarize(_ request: AIPeriodSummaryRequest) async throws -> AIPeriodSummaryText {
        do {
            return try await perform(request, forceRefresh: false)
        } catch AIPeriodSummaryClientError.unauthorized {
            return try await perform(request, forceRefresh: true)
        }
    }

    private func perform(_ payload: AIPeriodSummaryRequest, forceRefresh: Bool) async throws -> AIPeriodSummaryText {
        let configuration = try configurationProvider()
        let url = configuration.baseURL.appending(path: "ai/period-summary")
        let token = try await authService.accessToken(forceRefresh: forceRefresh)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(payload)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIPeriodSummaryClientError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw AIPeriodSummaryClientError.transport }
        switch http.statusCode {
        case 200:
            guard data.count <= maxResponseBytes else { throw AIPeriodSummaryClientError.invalidContract }
            do {
                return try JSONDecoder().decode(AIPeriodSummaryText.self, from: data)
            } catch {
                throw AIPeriodSummaryClientError.invalidContract
            }
        case 401:
            throw AIPeriodSummaryClientError.unauthorized
        case 429:
            throw AIPeriodSummaryClientError.rateLimited
        case 400, 422:
            throw AIPeriodSummaryClientError.invalidContract
        default:
            throw AIPeriodSummaryClientError.unavailable
        }
    }
}
