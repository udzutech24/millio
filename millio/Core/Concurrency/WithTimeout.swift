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
        
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
