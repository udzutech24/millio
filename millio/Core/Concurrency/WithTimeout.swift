import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    let timeoutNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
    let operationTask = Task {
        await operation()
    }

    return await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operationTask.value
        }

        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        operationTask.cancel()
        return result
    }
}
