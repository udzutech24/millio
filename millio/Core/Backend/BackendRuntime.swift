import CryptoKit
import Foundation

enum BackendRegion: String, CaseIterable, Sendable {
    case ru = "RU"
    case de = "DE"

    var analyticsValue: String { rawValue.lowercased() }
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

    func endpoint(for countryCode: String?) -> BackendEndpoint {
        if countryCode?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == BackendRegion.ru.rawValue {
            return ru
        }
        return de
    }

    func alternate(to endpoint: BackendEndpoint) -> BackendEndpoint {
        endpoint.region == .ru ? de : ru
    }

    static func live(
        environment: [String: String],
        infoDictionary: [String: Any]
    ) throws -> BackendEndpoints {
        let ru = try resolveURL(
            key: "RU_API_BASE_URL",
            environment: environment,
            infoDictionary: infoDictionary
        )
        let de = try resolveURL(
            key: "DE_API_BASE_URL",
            environment: environment,
            infoDictionary: infoDictionary
        )

        return BackendEndpoints(
            ru: BackendEndpoint(region: .ru, baseURL: ru),
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

        guard
            !rawValue.isEmpty,
            let url = URL(string: rawValue),
            url.host() != nil
        else {
            throw AuthServiceError.invalidConfiguration
        }

        return url
    }
}

struct BackendSessionRuntime: Equatable, Sendable {
    let selectedEndpoint: BackendEndpoint
    let preferredEndpoint: BackendEndpoint
    let fallbackActivated: Bool
    let forcedOverride: Bool

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
            Locale.autoupdatingCurrent.region?.identifier
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

    func resolve() async -> BackendSessionRuntime {
        let forcedEndpoint = forcedEndpointProvider(endpoints)
        let preferredEndpoint = forcedEndpoint ?? endpoints.endpoint(for: countryCodeProvider())

        if await probe(endpoint: preferredEndpoint, logPrefix: "preferred") {
            let runtime = BackendSessionRuntime(
                selectedEndpoint: preferredEndpoint,
                preferredEndpoint: preferredEndpoint,
                fallbackActivated: false,
                forcedOverride: forcedEndpoint != nil
            )
            logSelection(runtime)
            return runtime
        }

        guard forcedEndpoint == nil else {
            let runtime = BackendSessionRuntime(
                selectedEndpoint: preferredEndpoint,
                preferredEndpoint: preferredEndpoint,
                fallbackActivated: false,
                forcedOverride: true
            )
            logSelection(runtime)
            return runtime
        }

        let fallbackEndpoint = endpoints.alternate(to: preferredEndpoint)
        if await probe(endpoint: fallbackEndpoint, logPrefix: "fallback") {
            let runtime = BackendSessionRuntime(
                selectedEndpoint: fallbackEndpoint,
                preferredEndpoint: preferredEndpoint,
                fallbackActivated: true,
                forcedOverride: false
            )
            logSelection(runtime)
            return runtime
        }

        AppLogger.log(
            .warning,
            category: "Backend",
            "Backend probe failed for both regions. Keeping preferred backend \(preferredEndpoint.region.rawValue) at \(preferredEndpoint.baseURL.absoluteString)"
        )

        let runtime = BackendSessionRuntime(
            selectedEndpoint: preferredEndpoint,
            preferredEndpoint: preferredEndpoint,
            fallbackActivated: false,
            forcedOverride: false
        )
        logSelection(runtime)
        return runtime
    }

    private func probe(endpoint: BackendEndpoint, logPrefix: String) async -> Bool {
        let probeURL = endpoint.baseURL.appending(path: "runtime/server-info")
        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                AppLogger.log(.warning, category: "Backend", "Backend \(logPrefix) probe returned non-HTTP response for \(endpoint.baseURL.absoluteString)")
                return false
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                AppLogger.log(.warning, category: "Backend", "Backend \(logPrefix) probe failed with status \(httpResponse.statusCode) for \(endpoint.baseURL.absoluteString)")
                return false
            }

            let payload = try JSONDecoder().decode(ServerInfoResponse.self, from: data)
            let reportedRegion = payload.region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard
                !reportedRegion.isEmpty,
                let reportedURL = URL(string: payload.publicApiBaseUrl),
                reportedURL.host() != nil
            else {
                AppLogger.log(.warning, category: "Backend", "Backend \(logPrefix) probe returned invalid server-info payload for \(endpoint.baseURL.absoluteString)")
                return false
            }

            let reportedBaseURL = BackendEndpoint(region: endpoint.region, baseURL: reportedURL).baseURL

            if reportedRegion != endpoint.region.rawValue {
                AppLogger.log(
                    .warning,
                    category: "Backend",
                    "Backend \(logPrefix) probe region mismatch. Expected \(endpoint.region.rawValue), got \(reportedRegion)"
                )
            }

            if reportedBaseURL != endpoint.baseURL {
                AppLogger.log(
                    .warning,
                    category: "Backend",
                    "Backend \(logPrefix) probe publicApiBaseUrl mismatch. Expected \(endpoint.baseURL.absoluteString), got \(reportedBaseURL.absoluteString)"
                )
            }

            return true
        } catch {
            AppLogger.log(
                .warning,
                category: "Backend",
                "Backend \(logPrefix) probe failed for \(endpoint.baseURL.absoluteString): \(error.localizedDescription)"
            )
            return false
        }
    }

    private func logSelection(_ runtime: BackendSessionRuntime) {
        AppLogger.log(
            .info,
            category: "Backend",
            "Selected backend region=\(runtime.selectedEndpoint.region.rawValue) baseURL=\(runtime.selectedEndpoint.baseURL.absoluteString) fallbackActive=\(runtime.fallbackActivated) forcedOverride=\(runtime.forcedOverride)"
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

            if forcedRegion == BackendRegion.ru.rawValue {
                return endpoints.ru
            }

            if forcedRegion == BackendRegion.de.rawValue {
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
            if normalizedURL == endpoints.ru.baseURL {
                return endpoints.ru
            }
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
