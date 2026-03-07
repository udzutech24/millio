import Foundation

struct AuthConfiguration: Sendable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = Self.normalize(baseURL)
    }

    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) throws -> AuthConfiguration {
        let environmentURL = processInfo.environment["AUTH_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentURL,
           !environmentURL.isEmpty,
           let url = URL(string: environmentURL),
           url.host() != nil {
            return AuthConfiguration(baseURL: url)
        }

        let scheme = (
            processInfo.environment["AUTH_BASE_SCHEME"] ??
            bundle.object(forInfoDictionaryKey: "AUTH_BASE_SCHEME") as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let host = (
            processInfo.environment["AUTH_BASE_HOST"] ??
            bundle.object(forInfoDictionaryKey: "AUTH_BASE_HOST") as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let portRaw = (
            processInfo.environment["AUTH_BASE_PORT"] ??
            bundle.object(forInfoDictionaryKey: "AUTH_BASE_PORT") as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let path = (
            processInfo.environment["AUTH_BASE_PATH"] ??
            bundle.object(forInfoDictionaryKey: "AUTH_BASE_PATH") as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !scheme.isEmpty, !host.isEmpty else {
            throw AuthServiceError.invalidConfiguration
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port = Int(portRaw) {
            components.port = port
        }
        components.path = normalizedPath(path)

        guard let url = components.url else {
            throw AuthServiceError.invalidConfiguration
        }

        return AuthConfiguration(baseURL: url)
    }

    private static func normalize(_ baseURL: URL) -> URL {
        var value = baseURL.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value) ?? baseURL
    }

    private static func normalizedPath(_ path: String) -> String {
        guard !path.isEmpty else { return "" }
        return path.hasPrefix("/") ? path : "/" + path
    }
}
