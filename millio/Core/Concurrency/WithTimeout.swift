import Foundation

private final class TimeoutResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: T?
    private var didFinish = false

    func store(_ value: T) {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return }
        result = value
        didFinish = true
    }

    func completedResult() -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard didFinish else { return nil }
        return result
    }
}

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    let resultBox = TimeoutResultBox<T>()
    return await withTaskGroup(of: T?.self, returning: T?.self) { group in
        group.addTask {
            let value = await operation()
            resultBox.store(value)
            return value
        }

        group.addTask {
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            return resultBox.completedResult()
        }

        let value = await group.next() ?? nil
        group.cancelAll()
        return value
    }
}
