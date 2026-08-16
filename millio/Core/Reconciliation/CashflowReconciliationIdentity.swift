import Foundation

enum CashflowReconciliationIdentity {
    /// Reviewed bank rows have a provider-issued opaque identity that must converge across scopes
    /// even when local creation timestamps differ. All other transactions retain the established
    /// multiset fingerprint so legitimate same-value manual rows are not collapsed.
    static func fingerprint(for transaction: CashflowTransaction) -> ScopeFingerprint {
        if let source = transaction.importSourceRaw,
           let reference = transaction.importReferenceKey,
           !source.isEmpty,
           !reference.isEmpty {
            return "import|\(source)|\(reference)"
        }
        return transaction.transactionUniqueID
    }
}
