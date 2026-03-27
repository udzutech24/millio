import Foundation

private enum WithTimeoutError: Error {
    case timedOut
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async -> T) async -> T? {
    do {
        return try await withThrowingTaskGroup(of: T.self, returning: T?.self) { group in
            // Race the operation against a dedicated timeout task and cancel the loser.
            group.addTask {
                await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(max(0, seconds)))
                throw WithTimeoutError.timedOut
            }

            let result = try await group.next()
            group.cancelAll()
            return result
        }
    } catch is WithTimeoutError {
        return nil
    } catch {
        return nil
    }
}
