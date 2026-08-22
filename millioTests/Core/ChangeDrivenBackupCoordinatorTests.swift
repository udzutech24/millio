import Foundation
import Testing
@testable import millio

@MainActor
struct ChangeDrivenBackupCoordinatorTests {
    @Test("Finance mutations are backup relevant, restore notifications are not")
    func classifiesEvents() {
        #expect(ChangeDrivenBackupCoordinator.isBackupRelevant(FinanceEvent.transactionsUpdated))
        #expect(ChangeDrivenBackupCoordinator.isBackupRelevant(FinanceEvent.depositOperationCommitted))
        #expect(!ChangeDrivenBackupCoordinator.isBackupRelevant(BackupEvent.restoreCompleted))
    }

    @Test("Background flush backs up one coalesced dirty generation")
    func flushesDirtyStateOnce() async {
        var calls = 0
        let coordinator = ChangeDrivenBackupCoordinator(
            debounceNanoseconds: .max,
            canBackup: { true },
            backup: { calls += 1 }
        )
        coordinator.markDirty()
        coordinator.markDirty()

        await coordinator.flushIfNeeded()
        await coordinator.flushIfNeeded()

        #expect(calls == 1)
        #expect(!coordinator.isDirty)
        coordinator.stop()
    }

    @Test("Blocked flush retains dirty state for later retry")
    func blockedFlushRetainsDirtyState() async {
        var calls = 0
        let coordinator = ChangeDrivenBackupCoordinator(
            debounceNanoseconds: .max,
            canBackup: { false },
            backup: { calls += 1 }
        )
        coordinator.markDirty()

        await coordinator.flushIfNeeded()

        #expect(calls == 0)
        #expect(coordinator.isDirty)
        coordinator.stop()
    }
}

