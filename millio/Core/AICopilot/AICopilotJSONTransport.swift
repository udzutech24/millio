//
//  AICopilotJSONTransport.swift
//  millio
//

import Foundation

enum AICopilotClientError: Error, Equatable {
    case unavailable
    case unauthorized
    case rateLimited
    case transport
    case invalidContract
}

/// POST JSON к AI-эндпоинтам: Bearer-токен, один повтор при 401 и общий маппинг HTTP-статусов.
struct AICopilotJSONTransport {
    let authService: any AuthServiceProtocol
    let configurationProvider: @Sendable () throws -> AuthConfiguration
    let session: URLSession
    let maxResponseBytes: Int

    func post<Body: Encodable, Response: Decodable>(path: String, body: Body) async throws -> Response {
        do {
            return try await perform(path: path, body: body, forceRefresh: false)
        } catch AICopilotClientError.unauthorized {
            return try await perform(path: path, body: body, forceRefresh: true)
        }
    }

    private func perform<Body: Encodable, Response: Decodable>(
        path: String,
        body: Body,
        forceRefresh: Bool
    ) async throws -> Response {
        let configuration = try configurationProvider()
        let url = configuration.baseURL.appending(path: path)
        let token = try await authService.accessToken(forceRefresh: forceRefresh)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AICopilotClientError.transport
        }

        guard let http = response as? HTTPURLResponse else { throw AICopilotClientError.transport }
        switch http.statusCode {
        case 200:
            guard data.count <= maxResponseBytes else { throw AICopilotClientError.invalidContract }
            do {
                return try JSONDecoder().decode(Response.self, from: data)
            } catch {
                throw AICopilotClientError.invalidContract
            }
        case 401:
            throw AICopilotClientError.unauthorized
        case 429:
            throw AICopilotClientError.rateLimited
        case 400, 422:
            throw AICopilotClientError.invalidContract
        default:
            throw AICopilotClientError.unavailable
        }
    }
}
