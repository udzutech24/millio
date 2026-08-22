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
        // Доступность iCloud/backup должна проверяться всегда, даже если автобэкап выключен.
        await enabledManager.isAvailable()
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

    func saveVersionNow(passphrase: String?) async throws {
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.saveVersionNow(passphrase: passphrase)
        } else {
            try await disabledManager.saveVersionNow(passphrase: passphrase)
        }
    }

    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        try await enabledManager.exportVersion(recordName: recordName)
    }

    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        try await enabledManager.importVersion(from: data)
    }
    
    func restoreLatest() async throws {
        // Восстановление не зависит от тумблера автосоздания backup.
        try await enabledManager.restoreLatest()
    }
    
    func restoreLatest(passphrase: String?) async throws {
        // Восстановление не зависит от тумблера автосоздания backup.
        try await enabledManager.restoreLatest(passphrase: passphrase)
    }

    func restoreVersion(recordName: String, passphrase: String?) async throws {
        try await enabledManager.restoreVersion(recordName: recordName, passphrase: passphrase)
    }

    func restoreVersionVerified(
        recordName: String,
        passphrase: String?,
        progress: RecoveryProgressSink?
    ) async throws -> RecoveryReceipt {
        try await enabledManager.restoreVersionVerified(
            recordName: recordName,
            passphrase: passphrase,
            progress: progress
        )
    }

    func listBackupVersions() async -> [BackupVersionInfo] {
        await enabledManager.listBackupVersions()
    }

    func deleteBackupVersion(recordName: String) async throws {
        try await enabledManager.deleteBackupVersion(recordName: recordName)
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        // Информация о backup нужна и при выключенном автобэкапе (экран восстановления).
        await enabledManager.lastBackupInfo()
    }
}
