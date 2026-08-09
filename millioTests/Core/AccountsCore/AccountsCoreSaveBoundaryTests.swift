import SwiftData
import Testing
@testable import millio

@Suite("AccountsCoreSaveBoundary")
@MainActor
struct AccountsCoreSaveBoundaryTests {
    @Test("Save failure is typed and rolls back the owned context")
    func failedCommitIsTypedAndClean() throws {
        struct SaveFailure: Error {}
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(AccountGroup(name: "Must not persist"))
        let boundary = AccountsCoreSaveBoundary { _ in throw SaveFailure() }

        do {
            try boundary.commit(context, operation: .updateAccount)
            Issue.record("Expected a typed persistence failure")
        } catch let AccountsCorePersistenceError.saveFailed(operation, underlying) {
            #expect(operation == .updateAccount)
            #expect(underlying is SaveFailure)
        } catch {
            Issue.record("Unexpected error: \(type(of: error))")
        }

        #expect(!context.hasChanges)
        #expect(try context.fetchCount(FetchDescriptor<AccountGroup>()) == 0)
    }
}
