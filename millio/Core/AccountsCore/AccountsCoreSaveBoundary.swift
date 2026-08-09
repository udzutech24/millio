import SwiftData

/// Stable mutation labels let callers present persistence failures without parsing provider errors.
enum AccountsCoreSaveOperation: String, Sendable {
    case createProduct
    case updateAccount
}

/// Typed persistence failure at the AccountsCore trust boundary.
/// The underlying error is retained for local diagnostics but must not be shown or logged verbatim.
enum AccountsCorePersistenceError: Error {
    case saveFailed(operation: AccountsCoreSaveOperation, underlying: any Error)
}

/// Owns the only side effect shared by interactive AccountsCore mutation services: durable commit.
/// Call this only from a transaction that exclusively owns the context's pending changes.
@MainActor
struct AccountsCoreSaveBoundary {
    typealias SaveOperation = (ModelContext) throws -> Void

    private let saveOperation: SaveOperation

    /// Injected operations must preserve `ModelContext.save()` atomicity: never throw after a
    /// successful durable commit, otherwise a caller could incorrectly retry committed work.
    init(saveOperation: @escaping SaveOperation = { try $0.save() }) {
        self.saveOperation = saveOperation
    }

    func commit(_ context: ModelContext, operation: AccountsCoreSaveOperation) throws {
        do {
            try saveOperation(context)
        } catch {
            context.rollback()
            throw AccountsCorePersistenceError.saveFailed(operation: operation, underlying: error)
        }
    }
}
