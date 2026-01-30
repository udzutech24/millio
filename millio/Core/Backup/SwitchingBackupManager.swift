import Foundation

final class SwitchingBackupManager: BackupManagerProtocol {
    private let appState: AppState
    private let enabledManager: BackupManagerProtocol
    private let disabledManager: BackupManagerProtocol
    
    init(appState: AppState, enabled: BackupManagerProtocol, disabled: BackupManagerProtocol) {
        self.appState = appState
        self.enabledManager = enabled
        self.disabledManager = disabled
    }
    
    func isAvailable() async -> Bool {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        return await (enabled ? enabledManager.isAvailable() : disabledManager.isAvailable())
    }
    
    func backupNow() async throws {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.backupNow()
        } else {
            try await disabledManager.backupNow()
        }
    }
    
    func backupNow(passphrase: String?) async throws {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.backupNow(passphrase: passphrase)
        } else {
            try await disabledManager.backupNow(passphrase: passphrase)
        }
    }
    
    func restoreLatest() async throws {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.restoreLatest()
        } else {
            try await disabledManager.restoreLatest()
        }
    }
    
    func restoreLatest(passphrase: String?) async throws {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.restoreLatest(passphrase: passphrase)
        } else {
            try await disabledManager.restoreLatest(passphrase: passphrase)
        }
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        return await (enabled ? enabledManager.lastBackupInfo() : disabledManager.lastBackupInfo())
    }
}

