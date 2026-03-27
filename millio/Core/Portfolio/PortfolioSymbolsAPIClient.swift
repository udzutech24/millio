import Foundation

protocol HTTPSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPSessionProtocol {}

enum PortfolioSymbolsAPIClientError: LocalizedError, Equatable, Sendable {
    case invalidConfiguration
    case unconfigured
    case unauthorized(requestId: String? = nil)
    case backend(statusCode: Int, message: String, requestId: String? = nil)
    case transport(AuthTransportError)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Backend API base URL configuration is missing or invalid."
        case .unconfigured:
            return "Portfolio symbols API client is not configured yet."
        case .unauthorized:
            return "Session expired. Please sign in again."
        case .backend(_, let message, _):
            return message
        case .transport(let transportError):
            return transportError.errorDescription
        }
    }
}

protocol PortfolioSymbolsAPIClientProtocol: Sendable {
    func syncSymbols(_ symbols: [String]) async throws
}

private struct PortfolioSymbolsSyncRequest: Encodable {
    let symbols: [String]
}

private struct PortfolioSymbolsErrorEnvelope: Decodable {
    let message: String?
    let error: String?

    var resolvedMessage: String {
        message ?? error ?? "Failed to sync portfolio symbols."
    }
}

final class PortfolioSymbolsAPIClient: PortfolioSymbolsAPIClientProtocol, @unchecked Sendable {
    private let authService: any AuthServiceProtocol
    private let session: any HTTPSessionProtocol
    private let configurationProvider: @Sendable () throws -> AuthConfiguration
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        authService: any AuthServiceProtocol,
        configurationProvider: @escaping @Sendable () throws -> AuthConfiguration,
        session: any HTTPSessionProtocol = URLSession.shared
    ) {
        self.authService = authService
        self.session = session
        self.configurationProvider = configurationProvider
    }

    func syncSymbols(_ symbols: [String]) async throws {
        do {
            let accessToken = try await authService.accessToken(forceRefresh: false)
            try await request(symbols: symbols, accessToken: accessToken)
        } catch PortfolioSymbolsAPIClientError.unauthorized {
            let refreshedToken = try await authService.accessToken(forceRefresh: true)
            try await request(symbols: symbols, accessToken: refreshedToken)
        }
    }

    private func request(symbols: [String], accessToken: String) async throws {
        let configuration: AuthConfiguration
        do {
            configuration = try configurationProvider()
        } catch {
            throw PortfolioSymbolsAPIClientError.invalidConfiguration
        }

        guard var components = URLComponents(url: configuration.baseURL, resolvingAgainstBaseURL: false) else {
            throw PortfolioSymbolsAPIClientError.invalidConfiguration
        }

        components.path += "/portfolio/symbols"

        guard let url = components.url else {
            throw PortfolioSymbolsAPIClientError.invalidConfiguration
        }

        AppLogger.log(.debug, category: "PortfolioSymbolsSync", "Portfolio symbols sync started: \(url.absoluteString)")

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try encoder.encode(PortfolioSymbolsSyncRequest(symbols: symbols))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PortfolioSymbolsAPIClientError.transport(.network("Invalid portfolio symbols sync response."))
            }

            let requestId = httpResponse.value(forHTTPHeaderField: "x-request-id")

            switch httpResponse.statusCode {
            case 401:
                AppLogger.log(.warning, category: "PortfolioSymbolsSync", "Portfolio symbols sync unauthorized: \(url.absoluteString)")
                throw PortfolioSymbolsAPIClientError.unauthorized(requestId: requestId)
            case 200..<300:
                AppLogger.log(.info, category: "PortfolioSymbolsSync", "Portfolio symbols sync succeeded: \(url.absoluteString)")
                return
            default:
                let message = (try? decoder.decode(PortfolioSymbolsErrorEnvelope.self, from: data).resolvedMessage)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                AppLogger.log(
                    .warning,
                    category: "PortfolioSymbolsSync",
                    "Portfolio symbols sync failed with status \(httpResponse.statusCode): \(url.absoluteString)"
                )
                throw PortfolioSymbolsAPIClientError.backend(
                    statusCode: httpResponse.statusCode,
                    message: message,
                    requestId: requestId
                )
            }
        } catch let error as PortfolioSymbolsAPIClientError {
            throw error
        } catch {
            throw PortfolioSymbolsAPIClientError.transport(AuthTransportError.from(error))
        }
    }
}
