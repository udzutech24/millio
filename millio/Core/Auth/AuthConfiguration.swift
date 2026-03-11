import Foundation

struct AuthConfiguration: Sendable {
    let baseURL: URL

    init(baseURL: URL) {
        self.baseURL = Self.normalize(baseURL)
    }

    static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) throws -> AuthConfiguration {
        try live(
            environment: processInfo.environment,
            infoDictionary: bundle.infoDictionary ?? [:]
        )
    }

    static func live(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) throws -> AuthConfiguration {
        let environmentURL = environment["AUTH_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let environmentURL,
           !environmentURL.isEmpty,
           let url = URL(string: environmentURL),
           url.host() != nil {
            return AuthConfiguration(baseURL: url)
        }

        let scheme = (
            environment["AUTH_BASE_SCHEME"] ??
            infoDictionary["AUTH_BASE_SCHEME"] as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let host = (
            environment["AUTH_BASE_HOST"] ??
            infoDictionary["AUTH_BASE_HOST"] as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let portRaw = (
            environment["AUTH_BASE_PORT"] ??
            infoDictionary["AUTH_BASE_PORT"] as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        let path = (
            environment["AUTH_BASE_PATH"] ??
            infoDictionary["AUTH_BASE_PATH"] as? String ??
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
