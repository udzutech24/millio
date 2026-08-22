import Foundation

/// Availability is deliberately independent from authentication and data-scope selection.
/// `.offline` means that Millio backend is unavailable or not yet confirmed; it does not
/// make a claim about the device's Internet connection.
enum BackendAvailability: Equatable, Sendable {
    case checking
    case online
    case offline(BackendAvailabilityFailure)
}

enum BackendAvailabilityFailure: Error, Equatable, Sendable {
    case probeTimedOut
    case transport
    case rateLimited
    case server
    case unauthorized
    case cancelled
    case invalidResponse
}

/// Ограничивает частоту фоновых проверок после временной ошибки сети. Последняя задержка
/// повторяется, чтобы приложение восстанавливалось само, не превращаясь в частый polling.
enum BackendAvailabilityRetryPolicy {
    private static let delays: [Duration] = [
        .seconds(5),
        .seconds(15),
        .seconds(30),
        .seconds(60)
    ]

    static func delay(for failureCount: Int) -> Duration {
        let index = min(max(failureCount - 1, 0), delays.count - 1)
        return delays[index]
    }
}

/// Pure transition policy. Keeping it free of URLSession and SwiftUI makes the five-second
/// launch contract deterministic in tests and prevents a late availability result from
/// rebuilding the scope/navigation tree.
struct BackendAvailabilityStateMachine: Sendable {
    private(set) var state: BackendAvailability = .checking

    mutating func deadlineElapsed() {
        guard state == .checking else { return }
        state = .offline(.probeTimedOut)
    }

    mutating func probeSucceeded() {
        state = .online
    }

    mutating func probeFailed(_ failure: BackendAvailabilityFailure) {
        guard state != .online else { return }
        state = .offline(failure)
    }
}

struct BackendAvailabilityProbe: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(endpoint: BackendEndpoint) async -> Result<Void, BackendAvailabilityFailure> {
        let url = endpoint.baseURL.appending(path: "runtime/server-info")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The deadline is managed separately: do not cancel this request at T+5, because a
        // response at T+5.1 must clear only the indicator without resetting local UI.
        request.timeoutInterval = 30

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .failure(.invalidResponse) }
            switch http.statusCode {
            case 200..<300: return .success(())
            case 401, 403: return .failure(.unauthorized)
            case 429: return .failure(.rateLimited)
            case 500..<600: return .failure(.server)
            default: return .failure(.invalidResponse)
            }
        } catch is CancellationError {
            return .failure(.cancelled)
        } catch let error as URLError where error.code == .cancelled {
            return .failure(.cancelled)
        } catch {
            return .failure(.transport)
        }
    }
}
