import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    await withThrowingTaskGroup(of: T.self, returning: T?.self) { group in
        group.addTask {
            await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(max(0, seconds)))
            throw TimeoutError()
        }

        do {
            let value = try await group.next()
            group.cancelAll()
            return value
        } catch {
            group.cancelAll()
            return nil
        }
    }
}

private struct TimeoutError: Error {}
