import Foundation
import Testing
@testable import millio

actor SpyBackupManager: BackupManagerProtocol {
    private(set) var isAvailableCalls = 0
    private(set) var backupCalls = 0
    private(set) var restoreCalls = 0
    private(set) var infoCalls = 0
    
    let available: Bool
    private let versions: [BackupVersionInfo]

    init(available: Bool, versions: [BackupVersionInfo] = []) {
        self.available = available
        self.versions = versions
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
    
    func inspectBackupFile(_ data: Data) async throws -> BackupInfo {
        BackupInfo(date: Date(timeIntervalSince1970: 0), size: Int64(data.count), version: "1.0")
    }

    @discardableResult
    func restoreFromFile(_ data: Data, passphrase: String?) async throws -> RestoreReceipt {
        restoreCalls += 1
        return RestoreReceiptFixtures.verified
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
        return versions
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
        // R10: маршрутизация проверяется в авторизованном scope — в гостевом облачные
        // операции запрещены гейтом доступа (см. BackupGuestScopeAccessTests).
        let appState = await MainActor.run {
            let state = AppState()
            state.activeScopeKey = DataScope.user(id: "owner-1").storeConfigurationName
            return state
        }
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
        // R10: маршрутизация проверяется в авторизованном scope — в гостевом облачные
        // операции запрещены гейтом доступа (см. BackupGuestScopeAccessTests).
        let appState = await MainActor.run {
            let state = AppState()
            state.activeScopeKey = DataScope.user(id: "owner-1").storeConfigurationName
            return state
        }
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
