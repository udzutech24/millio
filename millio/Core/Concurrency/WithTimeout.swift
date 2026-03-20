import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    await withTaskGroup(of: T?.self, returning: T?.self) { group in
        group.addTask {
            await operation()
        }

        group.addTask {
            try? await Task.sleep(for: .seconds(max(0, seconds)))
            return nil
        }

        let value = await group.next() ?? nil
        group.cancelAll()
        return value

    }
}
