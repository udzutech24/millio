import Foundation

private final class TimeoutContinuationBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false

    func resume(_ continuation: CheckedContinuation<T?, Never>, with value: T?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true
        continuation.resume(returning: value)
    }
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    let timeoutSeconds = max(0, seconds)
    let box = TimeoutContinuationBox<T>()

    return await withCheckedContinuation { continuation in
        let operationTask = Task {
            let value = await operation()
            box.resume(continuation, with: value)
        }

        Task {
            try? await Task.sleep(for: .seconds(timeoutSeconds))
            operationTask.cancel()
            box.resume(continuation, with: nil)
        }
    }
}
