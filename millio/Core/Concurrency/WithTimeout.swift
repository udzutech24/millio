import Foundation

func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask {
            await operation()
        }
        
        group.addTask {
            try? await Task.sleep(for: .seconds(seconds))
            return nil
        }
        
        var result: T? = nil
        for await value in group {
            if let value {
                result = value
                break
            }
        }
        group.cancelAll()
        return result
    }
}
