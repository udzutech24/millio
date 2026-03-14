import Foundation

/// Backend auth endpoints that must be correlated with server logs through `x-request-id`.
enum AuthRequestOperation: String, Equatable, Sendable {
    case appleSignIn = "apple_sign_in"
    case refresh
    case logout
    case me

    var path: String {
        switch self {
        case .appleSignIn:
            return "auth/apple"
        case .refresh:
            return "auth/refresh"
        case .logout:
            return "auth/logout"
        case .me:
            return "auth/me"
        }
    }

    var method: String {
        switch self {
        case .me:
            return "GET"
        case .appleSignIn, .refresh, .logout:
            return "POST"
        }
    }
}

struct AuthResponseMetadata: Equatable, Sendable {
    let statusCode: Int
    let requestId: String?
    let clientRequestId: String
    let durationMilliseconds: Int
}

struct AuthDiagnosticsContext: Equatable, Sendable {
    let backendBaseURL: String
    let region: String

    init(backendBaseURL: String, region: String) {
        self.backendBaseURL = backendBaseURL
        self.region = region
    }

    init(configuration: AuthConfiguration) {
        self.init(
            backendBaseURL: configuration.baseURL.absoluteString,
            region: configuration.region.rawValue
        )
    }

    static let empty = AuthDiagnosticsContext(backendBaseURL: "", region: "")

    func fields(
        endpoint: String? = nil,
        statusCode: Int? = nil,
        requestId: String? = nil,
        errorType: String? = nil,
        reason: String? = nil
    ) -> [String: String] {
        var details: [String: String] = [
            "backendBaseURL": backendBaseURL,
            "region": region
        ]

        if let endpoint {
            details["endpoint"] = endpoint
        }
        if let statusCode {
            details["httpStatus"] = String(statusCode)
        }
        if let requestId {
            details["requestId"] = requestId
        }
        if let errorType {
            details["errorType"] = errorType
        }
        if let reason {
            details["reason"] = reason
        }

        return details
    }
}

struct AuthNetworkResult<Value: Sendable>: Sendable {
    let value: Value
    let metadata: AuthResponseMetadata
}

struct AuthClientMetadata: Equatable, Sendable {
    let platform: String
    let appVersion: String

    static func live(bundle: Bundle = .main) -> AuthClientMetadata {
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedVersion: String
        switch (shortVersion, build) {
        case let (.some(short), .some(build)) where !short.isEmpty && !build.isEmpty && short != build:
            resolvedVersion = "\(short)(\(build))"
        case let (.some(short), _) where !short.isEmpty:
            resolvedVersion = short
        case let (_, .some(build)) where !build.isEmpty:
            resolvedVersion = build
        default:
            resolvedVersion = "unknown"
        }

        return AuthClientMetadata(platform: "ios", appVersion: resolvedVersion)
    }
}

protocol AuthDiagnosticsLogging: Sendable {
    func log(
        _ level: LogLevel,
        phase: String,
        operation: AuthRequestOperation?,
        requestId: String?,
        backendRequestId: String?,
        details: [String: String]
    )
}

struct AuthDiagnosticsLogger: AuthDiagnosticsLogging {
    func log(
        _ level: LogLevel,
        phase: String,
        operation: AuthRequestOperation? = nil,
        requestId: String? = nil,
        backendRequestId: String? = nil,
        details: [String: String] = [:]
    ) {
        var segments: [String] = [phase]

        if let operation {
            segments.append("operation=\(operation.rawValue)")
        }
        if let requestId, !requestId.isEmpty {
            segments.append("requestId=\(requestId)")
        }
        if let backendRequestId, !backendRequestId.isEmpty {
            segments.append("backendRequestId=\(backendRequestId)")
        }

        let metadata = details
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
        segments.append(contentsOf: metadata)

        AppLogger.log(level, category: "AuthFlow", segments.joined(separator: " "))
    }
}

enum AuthDiagnosticsFields {
    static func token(_ name: String, value: String?) -> [String: String] {
        [
            "\(name)Present": value == nil ? "false" : "true",
            "\(name)Length": value.map { String($0.count) } ?? "0"
        ]
    }

    static func optionalString(_ name: String, value: String?) -> [String: String] {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return [
            "\(name)Present": (trimmed?.isEmpty == false) ? "true" : "false",
            "\(name)Length": trimmed.map { String($0.count) } ?? "0"
        ]
    }

    static func bool(_ name: String, value: Bool) -> [String: String] {
        [name: value ? "true" : "false"]
    }
}
