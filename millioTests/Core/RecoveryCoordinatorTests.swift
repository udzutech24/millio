import Foundation
import Testing
@testable import millio

@MainActor
struct RecoveryCoordinatorTests {
    @Test("Clean install discovers backup in authenticated scope before onboarding")
    func discoversBackupForAuthenticatedEmptyScope() async {
        let manager = RecoveryBackupManagerStub(versions: [Self.version])
        let token = RecoveryScopeToken(kind: .authenticated, generation: 1)
        let coordinator = RecoveryCoordinator(
            backupManager: manager,
            localModelCount: { 0 },
            isScopeCurrent: { $0 == token }
        )

        await coordinator.discover(scope: token)

        #expect(coordinator.state == .awaitingConfirmation(Self.version))
    }

    @Test("Guest scope is rejected before backup lookup")
    func rejectsGuestScope() async {
        let manager = RecoveryBackupManagerStub()
        let coordinator = RecoveryCoordinator(
            backupManager: manager,
            localModelCount: { 0 },
            isScopeCurrent: { _ in true }
        )

        await coordinator.discover(
            scope: RecoveryScopeToken(kind: .guest, generation: 0)
        )

        #expect(coordinator.state == .failed(.invalidScope))
        #expect(await manager.listCallCount() == 0)
    }

    @Test("Non-empty local store is never offered destructive recovery")
    func rejectsNonEmptyStore() async {
        let manager = RecoveryBackupManagerStub()
        let token = RecoveryScopeToken(kind: .authenticated, generation: 2)
        let coordinator = RecoveryCoordinator(
            backupManager: manager,
            localModelCount: { 7 },
            isScopeCurrent: { $0 == token }
        )

        await coordinator.discover(scope: token)

        #expect(coordinator.state == .failed(.localDataPresent(count: 7)))
        #expect(await manager.listCallCount() == 0)
    }

    @Test("Verified restore publishes receipt after all stages")
    func verifiedRestorePublishesReceipt() async {
        let manager = RecoveryBackupManagerStub(
            versions: [Self.version],
            receipt: Self.receipt
        )
        let token = RecoveryScopeToken(kind: .authenticated, generation: 3)
        let coordinator = RecoveryCoordinator(
            backupManager: manager,
            localModelCount: { 0 },
            isScopeCurrent: { $0 == token }
        )
        await coordinator.discover(scope: token)

        coordinator.restoreConfirmed(recordName: Self.version.recordName, passphrase: nil)
        for _ in 0..<20 where coordinator.state != .succeeded(Self.receipt) {
            await Task.yield()
        }

        #expect(coordinator.state == .succeeded(Self.receipt))
        #expect(await manager.restoreCallCount() == 1)
    }

    private static let version = BackupVersionInfo(
        recordName: "fixture",
        date: Date(timeIntervalSince1970: 10),
        size: 1_024,
        version: "2.0.0",
        isPinned: false
    )

    private static let receipt = RecoveryReceipt(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000009")!,
        backupDate: Date(timeIntervalSince1970: 10),
        expectedModelCount: 4,
        localModelCountBefore: 0,
        importedModelCount: 4,
        localModelCountAfter: 4,
        duration: 1
    )
}

private actor RecoveryBackupManagerStub: BackupManagerProtocol {
    private var versions: [BackupVersionInfo]
    private var receipt: RecoveryReceipt?
    var listCalls = 0
    var restoreCalls = 0

    init(
        versions: [BackupVersionInfo] = [],
        receipt: RecoveryReceipt? = nil
    ) {
        self.versions = versions
        self.receipt = receipt
    }

    func isAvailable() async -> Bool { true }
    func backupNow() async throws {}
    func backupNow(passphrase: String?) async throws {}
    func saveVersionNow(passphrase: String?) async throws {}
    func exportVersion(recordName: String) async throws -> BackupTransferPayload { throw AppError.iCloudUnavailable }
    func importVersion(from data: Data) async throws -> BackupVersionInfo { throw AppError.iCloudUnavailable }
    func restoreLatest() async throws {}
    func restoreLatest(passphrase: String?) async throws {}
    func restoreVersion(recordName: String, passphrase: String?) async throws {}
    func restoreVersionVerified(recordName: String, passphrase: String?, progress: RecoveryProgressSink?) async throws -> RecoveryReceipt {
        restoreCalls += 1
        await progress?(.downloading)
        await progress?(.validating)
        await progress?(.importing)
        await progress?(.verifying)
        await progress?(.finishing)
        guard let receipt else { throw RecoveryFailure.noBackup }
        return receipt
    }
    func listBackupVersions() async -> [BackupVersionInfo] {
        listCalls += 1
        return versions
    }
    func deleteBackupVersion(recordName: String) async throws {}
    func lastBackupInfo() async -> BackupInfo? { nil }
    func listCallCount() -> Int { listCalls }
    func restoreCallCount() -> Int { restoreCalls }
}
