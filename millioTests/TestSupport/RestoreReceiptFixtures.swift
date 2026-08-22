import Foundation
@testable import millio

/// Готовые receipt'ы для моков `BackupManagerProtocol`, чтобы каждый мок не собирал их руками.
enum RestoreReceiptFixtures {
    static let verified = RestoreReceipt(
        expectedModelCount: 1,
        importedModelCount: 1,
        expectedByType: ["Item": 1],
        importedByType: ["Item": 1]
    )
}
