import Foundation

struct AuthConfiguration: Sendable {
    let baseURL: URL
    let region: BackendRegion
    private static let productionDEBaseURL = URL(string: "https://api.iqdrop.ru/api/v1")!

    init(baseURL: URL, region: BackendRegion = .de) {
        self.baseURL = Self.normalize(baseURL)
        self.region = region
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
           let url = validatedURL(environmentURL) {
            return AuthConfiguration(baseURL: url, region: .de)
        }

        if let deBaseURL = environment["DE_API_BASE_URL"] ?? infoDictionary["DE_API_BASE_URL"] as? String {
            let trimmed = deBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            if let url = validatedURL(trimmed) {
                return AuthConfiguration(baseURL: url, region: .de)
            }
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
            return AuthConfiguration(baseURL: productionDEBaseURL, region: .de)
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if let port = Int(portRaw) {
            components.port = port
        }
        components.path = normalizedPath(path)

        guard let url = components.url else {
            return AuthConfiguration(baseURL: productionDEBaseURL, region: .de)
        }

        return AuthConfiguration(baseURL: url, region: .de)
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

    private static func validatedURL(_ rawValue: String) -> URL? {
        guard
            !rawValue.isEmpty,
            rawValue.contains("$(") == false,
            let url = URL(string: rawValue),
            url.host() != nil
        else {
            return nil
        }

        return url
    }
}
