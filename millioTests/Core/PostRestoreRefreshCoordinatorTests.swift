import Foundation
import Testing
@testable import millio

@MainActor
struct PostRestoreRefreshCoordinatorTests {
    @Test("Verified receipt triggers one unified refresh")
    func refreshesOncePerReceipt() {
        EventBus.shared.removeAllSubscribers()
        defer { EventBus.shared.removeAllSubscribers() }
        var receiptIDs: [UUID] = []
        let coordinator = PostRestoreRefreshCoordinator { receipt in
            receiptIDs.append(receipt.id)
        }
        let receipt = RecoveryReceipt(
            id: UUID(),
            backupDate: nil,
            expectedModelCount: 2,
            localModelCountBefore: 0,
            importedModelCount: 2,
            localModelCountAfter: 2,
            duration: 1
        )
        coordinator.start()

        EventBus.shared.publish(BackupEvent.restoreVerified(receipt))
        EventBus.shared.publish(BackupEvent.restoreVerified(receipt))

        #expect(receiptIDs == [receipt.id])
        coordinator.stop()
    }
}

