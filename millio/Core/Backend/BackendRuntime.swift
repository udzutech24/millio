import CryptoKit
import Foundation

enum BackendRegion: String, CaseIterable, Sendable {
    case ru = "RU"
    case de = "DE"

    var analyticsValue: String { rawValue.lowercased() }
}

enum BackendSelectionSource: String, Sendable {
    case automaticLocale
    case debugOverride
    case configurationFallback
}

struct SystemCountryCodeResolver {
    static func resolve(
        autoupdatingLocale: Locale = .autoupdatingCurrent,
        currentLocale: Locale = .current,
        preferredLanguages: [String] = Locale.preferredLanguages
    ) -> String? {
        let candidates = [
            regionIdentifier(from: autoupdatingLocale),
            regionIdentifier(from: currentLocale),
            regionIdentifier(from: autoupdatingLocale.identifier),
            regionIdentifier(from: currentLocale.identifier)
        ] + preferredLanguages.map(regionIdentifier(from:))

        for candidate in candidates {
            guard let normalized = normalizeCountryCode(candidate) else { continue }
            return normalized
        }

        return nil
    }

    private static func regionIdentifier(from locale: Locale) -> String? {
        if let region = locale.region?.identifier {
            return region
        }

        return regionIdentifier(from: locale.identifier)
    }

    private static func regionIdentifier(from identifier: String) -> String? {
        let normalizedIdentifier = identifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")

        guard !normalizedIdentifier.isEmpty else { return nil }

        let locale = Locale(identifier: normalizedIdentifier)
        if let region = locale.region?.identifier {
            return region
        }

        let components = normalizedIdentifier.split(separator: "_")
        guard components.count >= 2 else { return nil }
        return String(components.last ?? "")
    }

    private static func normalizeCountryCode(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count >= 2 else { return nil }
        return trimmed
    }
}

struct BackendEndpoint: Equatable, Sendable {
    let region: BackendRegion
    let baseURL: URL

    init(region: BackendRegion, baseURL: URL) {
        self.region = region
        self.baseURL = Self.normalize(baseURL)
    }

    private static func normalize(_ baseURL: URL) -> URL {
        var value = baseURL.absoluteString
        while value.hasSuffix("/") {
            value.removeLast()
        }
        return URL(string: value) ?? baseURL
    }
}

struct BackendEndpoints: Equatable, Sendable {
    let ru: BackendEndpoint
    let de: BackendEndpoint

    private static let productionDefaults: [String: URL] = [
        "RU_API_BASE_URL": URL(string: "https://api.iqdrop.ru/api/v1")!,
        "DE_API_BASE_URL": URL(string: "https://api.iqdrop.ru/api/v1")!
    ]

    func endpoint(for countryCode: String?) -> BackendEndpoint {
        return de
    }

    func alternate(to endpoint: BackendEndpoint) -> BackendEndpoint {
        de
    }

    static func live(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) throws -> BackendEndpoints {
        let de = try resolveURL(
            key: "DE_API_BASE_URL",
            environment: environment,
            infoDictionary: infoDictionary
        )

        return BackendEndpoints(
            ru: BackendEndpoint(region: .ru, baseURL: de),
            de: BackendEndpoint(region: .de, baseURL: de)
        )
    }

    private static func resolveURL(
        key: String,
        environment: [String: String],
        infoDictionary: [String: Any]
    ) throws -> URL {
        let rawValue = (
            environment[key] ??
            infoDictionary[key] as? String ??
            ""
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = validatedURL(rawValue) {
            return url
        }

        if let defaultURL = productionDefaults[key] {
            AppLogger.log(
                .warning,
                category: "Backend",
                "Missing or invalid \(key) in runtime configuration. Falling back to bundled production default \(defaultURL.absoluteString)"
            )
            return defaultURL
        }

        throw AuthServiceError.invalidConfiguration
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

struct BackendSessionRuntime: Equatable, Sendable {
    let selectedEndpoint: BackendEndpoint
    let preferredEndpoint: BackendEndpoint
    let fallbackActivated: Bool
    let forcedOverride: Bool
    let selectionSource: BackendSelectionSource
    let detectedCountryCode: String?

    var authConfiguration: AuthConfiguration {
        AuthConfiguration(
            baseURL: selectedEndpoint.baseURL,
            region: selectedEndpoint.region
        )
    }

    var refreshTokenAccountKey: String {
        let hash = SHA256
            .hash(data: Data(selectedEndpoint.baseURL.absoluteString.lowercased().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "refreshToken.\(selectedEndpoint.region.analyticsValue).\(hash)"
    }

    var sessionSnapshotStorageKey: String {
        let hash = SHA256
            .hash(data: Data(selectedEndpoint.baseURL.absoluteString.lowercased().utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return "auth.sessionSnapshot.\(selectedEndpoint.region.analyticsValue).\(hash)"
    }

    var selectionSummaryLine: String {
        switch selectionSource {
        case .debugOverride:
            return "Selection: Debug override"
        case .automaticLocale:
            let countryCode = detectedCountryCode ?? "unknown"
            return "Selection: Auto (\(countryCode))"
        case .configurationFallback:
            let countryCode = detectedCountryCode ?? "unknown"
            return "Selection: Config fallback (\(countryCode))"
        }
    }
}

struct BackendStartupResolver {
    private struct ServerInfoResponse: Decodable {
        let region: String
        let publicApiBaseUrl: String
    }

    private let endpoints: BackendEndpoints
    private let session: URLSession
    private let countryCodeProvider: @Sendable () -> String?
    private let forcedEndpointProvider: @Sendable (BackendEndpoints) -> BackendEndpoint?

    init(
        endpoints: BackendEndpoints,
        session: URLSession = .shared,
        countryCodeProvider: @escaping @Sendable () -> String? = {
            SystemCountryCodeResolver.resolve()
        },
        forcedEndpointProvider: @escaping @Sendable (BackendEndpoints) -> BackendEndpoint? = Self.liveForcedEndpointProvider(
            environment: ProcessInfo.processInfo.environment,
            infoDictionary: Bundle.main.infoDictionary ?? [:]
        )
    ) {
        self.endpoints = endpoints
        self.session = session
        self.countryCodeProvider = countryCodeProvider
        self.forcedEndpointProvider = forcedEndpointProvider
    }

    /// Legacy test helper retained for endpoint-selection tests. Production startup must use
    /// `resolveStaticRuntime()` and run availability independently after local UI is ready.
    func resolve() async -> BackendSessionRuntime {
        resolveStaticRuntime()
    }

    func resolveStaticRuntime() -> BackendSessionRuntime {
        let forcedEndpoint = forcedEndpointProvider(endpoints)
        let detectedCountryCode = countryCodeProvider()
        let selectionSource: BackendSelectionSource
        let preferredEndpoint: BackendEndpoint

        if let forcedEndpoint {
            preferredEndpoint = forcedEndpoint
            selectionSource = .debugOverride
        } else {
            preferredEndpoint = endpoints.endpoint(for: detectedCountryCode)
            selectionSource = .automaticLocale
        }

        let runtime = BackendSessionRuntime(
            selectedEndpoint: preferredEndpoint,
            preferredEndpoint: preferredEndpoint,
            fallbackActivated: false,
            forcedOverride: forcedEndpoint != nil,
            selectionSource: selectionSource,
            detectedCountryCode: detectedCountryCode
        )
        logSelection(runtime)
        return runtime
    }

    private func logSelection(_ runtime: BackendSessionRuntime) {
        AppLogger.log(
            .info,
            category: "Backend",
            "Selected backend region=\(runtime.selectedEndpoint.region.rawValue) baseURL=\(runtime.selectedEndpoint.baseURL.absoluteString) fallbackActive=\(runtime.fallbackActivated) forcedOverride=\(runtime.forcedOverride) selectionSource=\(runtime.selectionSource.rawValue) detectedCountryCode=\(runtime.detectedCountryCode ?? "unknown")"
        )
    }

    private static func liveForcedEndpointProvider(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) -> @Sendable (BackendEndpoints) -> BackendEndpoint? {
        { endpoints in
            #if DEBUG
            let forcedRegion = (
                environment["BACKEND_FORCE_REGION"] ??
                infoDictionary["BACKEND_FORCE_REGION"] as? String
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

            if forcedRegion == BackendRegion.de.rawValue {
                return endpoints.de
            }

            if forcedRegion == BackendRegion.ru.rawValue {
                return endpoints.de
            }

            let forcedBaseURL = (
                environment["BACKEND_FORCE_BASE_URL"] ??
                infoDictionary["BACKEND_FORCE_BASE_URL"] as? String
            )?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard
                let forcedBaseURL,
                !forcedBaseURL.isEmpty,
                let url = URL(string: forcedBaseURL),
                url.host() != nil
            else {
                return nil
            }

            let normalizedURL = BackendEndpoint(region: .de, baseURL: url).baseURL
            if normalizedURL == endpoints.de.baseURL {
                return endpoints.de
            }

            let resolvedRegion = BackendRegion(rawValue: forcedRegion ?? "") ?? .de
            return BackendEndpoint(region: resolvedRegion, baseURL: normalizedURL)
            #else
            return nil
            #endif
        }
    }
}
