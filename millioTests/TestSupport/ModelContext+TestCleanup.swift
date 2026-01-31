import SwiftData

extension ModelContext {
    func deleteAll<T: PersistentModel>(_ model: T.Type) throws {
        let items = try fetch(FetchDescriptor<T>())
        for item in items {
            delete(item)
        }
    }
}

