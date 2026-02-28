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
    
    func restoreLatest() async throws {
        restoreCalls += 1
    }
    
    func restoreLatest(passphrase: String?) async throws {
        restoreCalls += 1
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        infoCalls += 1
        return nil
    }
}

struct SwitchingBackupManagerTests {
    @Test("SwitchingBackupManager routes calls based on appState.isBackupEnabled")
    func testSwitchingBackupManagerRoutesCalls() async throws {
        let appState = await MainActor.run { AppState() }
        let enabledSpy = SpyBackupManager(available: true)
        let disabledSpy = SpyBackupManager(available: false)
        let manager = SwitchingBackupManager(appState: appState, enabled: enabledSpy, disabled: disabledSpy)
        
        await MainActor.run { appState.isBackupEnabled = false }
        _ = await manager.isAvailable()
        try await manager.backupNow()
        
        await MainActor.run { appState.isBackupEnabled = true }
        _ = await manager.isAvailable()
        try await manager.backupNow()
        
        let enabledAvailableCalls = await enabledSpy.isAvailableCalls
        let disabledAvailableCalls = await disabledSpy.isAvailableCalls
        let enabledBackupCalls = await enabledSpy.backupCalls
        let disabledBackupCalls = await disabledSpy.backupCalls
        
        #expect(disabledAvailableCalls == 1)
        #expect(enabledAvailableCalls == 1)
        #expect(disabledBackupCalls == 1)
        #expect(enabledBackupCalls == 1)
    }
}

