import Foundation
import Testing
@testable import millio

actor SpyBackupManager: BackupManagerProtocol {
    private(set) var isAvailableCalls = 0
    private(set) var backupCalls = 0
    private(set) var restoreCalls = 0
    private(set) var infoCalls = 0
    
    let available: Bool
    
    init(available: Bool) {
        self.available = available
    }
    
    func isAvailable() async -> Bool {
        isAvailableCalls += 1
        return available
    }
    
    func backupNow() async throws {
        backupCalls += 1
    }
    
    func backupNow(passphrase: String?) async throws {
        backupCalls += 1
    }

    func saveVersionNow(passphrase: String?) async throws {
        backupCalls += 1
    }

    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        BackupTransferPayload(
            fileName: "backup.milliobackup",
            data: Data(),
            versionInfo: BackupVersionInfo(
                recordName: recordName,
                date: Date(timeIntervalSince1970: 0),
                size: 0,
                version: "1.0",
                isPinned: true
            )
        )
    }

    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        BackupVersionInfo(
            recordName: "snapshot-imported",
            date: Date(timeIntervalSince1970: 0),
            size: Int64(data.count),
            version: "1.0",
            isPinned: true
        )
    }
    
    func restoreLatest() async throws -> RestoreReceipt {
        restoreCalls += 1
        return RestoreReceiptFixtures.verified
    }

    func restoreLatest(passphrase: String?) async throws -> RestoreReceipt {
        restoreCalls += 1
        return RestoreReceiptFixtures.verified
    }

    func restoreVersion(recordName: String, passphrase: String?) async throws -> RestoreReceipt {
        restoreCalls += 1
        return RestoreReceiptFixtures.verified
    }

    func listBackupVersions() async -> [BackupVersionInfo] {
        infoCalls += 1
        return []
    }

    func deleteBackupVersion(recordName: String) async throws {}
    
    func lastBackupInfo() async -> BackupInfo? {
        infoCalls += 1
        return nil
    }
}

struct SwitchingBackupManagerTests {
    @Test("SwitchingBackupManager routes only backup creation by appState.isBackupEnabled")
    func testSwitchingBackupManagerRoutesBackupCreationByToggle() async throws {
        let appState = await MainActor.run { AppState() }
        let enabledSpy = SpyBackupManager(available: true)
        let disabledSpy = SpyBackupManager(available: false)
        let manager = SwitchingBackupManager(appState: appState, enabled: enabledSpy, disabled: disabledSpy)
        
        await MainActor.run { appState.isBackupEnabled = false }
        try await manager.backupNow()
        
        await MainActor.run { appState.isBackupEnabled = true }
        try await manager.backupNow()
        
        let enabledBackupCalls = await enabledSpy.backupCalls
        let disabledBackupCalls = await disabledSpy.backupCalls
        
        #expect(disabledBackupCalls == 1)
        #expect(enabledBackupCalls == 1)
    }

    @Test("SwitchingBackupManager always uses enabled manager for restore and backup status")
    func testSwitchingBackupManagerAlwaysUsesEnabledForRestoreAndStatus() async throws {
        let appState = await MainActor.run { AppState() }
        let enabledSpy = SpyBackupManager(available: true)
        let disabledSpy = SpyBackupManager(available: false)
        let manager = SwitchingBackupManager(appState: appState, enabled: enabledSpy, disabled: disabledSpy)

        await MainActor.run { appState.isBackupEnabled = false }
        _ = await manager.isAvailable()
        _ = await manager.lastBackupInfo()
        try await manager.restoreLatest()
        try await manager.restoreLatest(passphrase: "secret")

        await MainActor.run { appState.isBackupEnabled = true }
        _ = await manager.isAvailable()
        _ = await manager.lastBackupInfo()
        try await manager.restoreLatest()
        try await manager.restoreLatest(passphrase: nil)

        let enabledAvailableCalls = await enabledSpy.isAvailableCalls
        let disabledAvailableCalls = await disabledSpy.isAvailableCalls
        let enabledRestoreCalls = await enabledSpy.restoreCalls
        let disabledRestoreCalls = await disabledSpy.restoreCalls
        let enabledInfoCalls = await enabledSpy.infoCalls
        let disabledInfoCalls = await disabledSpy.infoCalls

        #expect(enabledAvailableCalls == 2)
        #expect(disabledAvailableCalls == 0)
        #expect(enabledInfoCalls == 2)
        #expect(disabledInfoCalls == 0)
        #expect(enabledRestoreCalls == 4)
        #expect(disabledRestoreCalls == 0)
    }
}
