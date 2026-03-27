import Foundation

enum AdminStatsAPIClientError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case unconfigured
    case unauthorized(requestId: String? = nil)
    case forbidden(message: String, requestId: String? = nil)
    case backend(statusCode: Int, message: String, requestId: String? = nil)
    case transport(AuthTransportError)
    case decodingFailed(requestId: String? = nil)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Backend API base URL configuration is missing or invalid."
        case .unconfigured:
            return "Admin stats API client is not configured yet."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .forbidden(let message, _),
             .backend(_, let message, _):
            return message
        case .transport(let transportError):
            return transportError.errorDescription
        case .decodingFailed:
            return "Failed to decode admin statistics."
        }
    }
}

protocol AdminStatsAPIClientProtocol: Sendable {
    func fetchOverview() async throws -> AdminStatsOverviewResponse
    func fetchSymbols(limit: Int) async throws -> AdminStatsSymbolsResponse
}

private struct AdminStatsErrorEnvelope: Decodable {
    let message: MessageValue?
    let error: String?

    enum MessageValue: Decodable {
        case string(String)
        case array([String])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(String.self) {
                self = .string(value)
                return
            }
            if let value = try? container.decode([String].self) {
                self = .array(value)
                return
            }
            throw DecodingError.typeMismatch(
                MessageValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported admin stats error format")
            )
        }
    }

    var resolvedMessage: String {
        switch message {
        case .string(let value):
            return value
        case .array(let values):
            return values.joined(separator: ", ")
        case nil:
            return error ?? "Failed to load admin statistics."
        }
    }
}

final class AdminStatsAPIClient: AdminStatsAPIClientProtocol, @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let session: URLSession
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let decoder: JSONDecoder

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: URLSession = .shared
    ) {
        self.authService = authService
        self.session = session
        self.configurationProvider = configurationProvider
        self.decoder = Self.makeDecoder()
    }

    func fetchOverview() async throws -> AdminStatsOverviewResponse {
        try await authorizedRequest(
            path: "admin/stats/overview",
            queryItems: []
        )
    }

    func fetchSymbols(limit: Int) async throws -> AdminStatsSymbolsResponse {
        try await authorizedRequest(
            path: "admin/stats/symbols",
            queryItems: [URLQueryItem(name: "limit", value: String(max(1, limit)))]
        )
    }

    private func authorizedRequest<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            return try await request(path: path, accessToken: accessToken, queryItems: queryItems)
        } catch AdminStatsAPIClientError.unauthorized {
            let refreshedToken = try await authService.accessToken(forceRefresh: true)
            return try await request(path: path, accessToken: refreshedToken, queryItems: queryItems)
        }
    }

    private func request<Response: Decodable>(
        path: String,
        accessToken: String,
        queryItems: [URLQueryItem]
    ) async throws -> Response {
        let configuration: AuthConfiguration
        do {
            configuration = try configurationProvider()
        } catch {
            throw AdminStatsAPIClientError.invalidConfiguration
        }

        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw AdminStatsAPIClientError.invalidConfiguration
        }

        let normalizedPath = path.hasPrefix("/") ? path : "/" + path
        components.path += normalizedPath
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AdminStatsAPIClientError.invalidConfiguration
        }

        AppLogger.log(.debug, category: "AdminStats", "Admin stats request started: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw AdminStatsAPIClientError.transport(.network("Invalid admin stats response."))
            }

            let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id")

            switch httpResponse.statusCode {
            case 401:
                AppLogger.log(.warning, category: "AdminStats", "Admin stats request unauthorized: \(url.absoluteString)")
                throw AdminStatsAPIClientError.unauthorized(requestId: requestId)
            case 403:
                let message = (try? decoder.decode(AdminStatsErrorEnvelope.self, from: data).resolvedMessage)
                    ?? "ADMIN access is required to view this screen."
                AppLogger.log(.warning, category: "AdminStats", "Admin stats request forbidden: \(url.absoluteString)")
                throw AdminStatsAPIClientError.forbidden(message: message, requestId: requestId)
            case 200..<300:
                AppLogger.log(.info, category: "AdminStats", "Admin stats request succeeded: \(url.absoluteString)")
                break
            default:
                let message = (try? decoder.decode(AdminStatsErrorEnvelope.self, from: data).resolvedMessage)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                AppLogger.log(
                    .warning,
                    category: "AdminStats",
                    "Admin stats request failed with status \(httpResponse.statusCode): \(url.absoluteString)"
                )
                throw AdminStatsAPIClientError.backend(
                    statusCode: httpResponse.statusCode,
                    message: message,
                    requestId: requestId
                )
            }

            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw AdminStatsAPIClientError.decodingFailed(requestId: requestId)
            }
        } catch let error as AdminStatsAPIClientError {
            throw error
        } catch {
            throw AdminStatsAPIClientError.transport(AuthTransportError.from(error))
        }
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatter.date(from: value) {
                return date
            }

            let fallback = ISO8601DateFormatter()
            fallback.formatOptions = [.withInternetDateTime]
            if let date = fallback.date(from: value) {
                return date
            }

            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date: \(value)"
            )
        }
        return decoder
    }
}
