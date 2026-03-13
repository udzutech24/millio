import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    return await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }

        group.addTask {
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            return nil
        }

        for await value in group {
            group.cancelAll()
            return value
        }

        return nil
    }
}
