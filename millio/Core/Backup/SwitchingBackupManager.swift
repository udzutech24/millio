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
    
    /// R10: гейт доступа к облачным копиям на уровне сервиса. Гостевой стор не имеет права
    /// ни читать, ни писать CloudKit — см. `BackupAccessPolicy`.
    private func requireCloudAccess() async throws {
        guard await isCloudAccessAllowed else { throw BackupAccessPolicy.denialError }
    }

    private var isCloudAccessAllowed: Bool {
        get async {
            await MainActor.run {
                BackupAccessPolicy.isCloudAccessAllowed(scopeKey: appState.activeScopeKey)
            }
        }
    }

    func isAvailable() async -> Bool {
        // Доступность iCloud/backup должна проверяться всегда, даже если автобэкап выключен.
        await enabledManager.isAvailable()
    }
    
    func backupNow() async throws {
        try await requireCloudAccess()
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.backupNow()
        } else {
            try await disabledManager.backupNow()
        }
    }
    
    func backupNow(passphrase: String?) async throws {
        try await requireCloudAccess()
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.backupNow(passphrase: passphrase)
        } else {
            try await disabledManager.backupNow(passphrase: passphrase)
        }
    }

    func saveVersionNow(passphrase: String?) async throws {
        try await requireCloudAccess()
        let enabled = await MainActor.run { appState.isBackupEnabled }
        if enabled {
            try await enabledManager.saveVersionNow(passphrase: passphrase)
        } else {
            try await disabledManager.saveVersionNow(passphrase: passphrase)
        }
    }

    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        try await requireCloudAccess()
        return try await enabledManager.exportVersion(recordName: recordName)
    }

    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        try await requireCloudAccess()
        return try await enabledManager.importVersion(from: data)
    }

    func inspectBackupFile(_ data: Data) async throws -> BackupInfo {
        // Разбор файла и восстановление из него не зависят от тумблера автосоздания backup.
        // Но гостю разбирать файл незачем: восстановить его всё равно некуда (R10) — отказ должен
        // прийти до деструктивного диалога, а не после подтверждения.
        try await requireCloudAccess()
        return try await enabledManager.inspectBackupFile(data)
    }

    @discardableResult
    func restoreFromFile(_ data: Data, passphrase: String?) async throws -> RestoreReceipt {
        try await requireCloudAccess()
        return try await enabledManager.restoreFromFile(data, passphrase: passphrase)
    }

    @discardableResult
    func restoreLatest() async throws -> RestoreReceipt {
        // Восстановление не зависит от тумблера автосоздания backup.
        try await requireCloudAccess()
        return try await enabledManager.restoreLatest()
    }

    @discardableResult
    func restoreLatest(passphrase: String?) async throws -> RestoreReceipt {
        // Восстановление не зависит от тумблера автосоздания backup.
        try await requireCloudAccess()
        return try await enabledManager.restoreLatest(passphrase: passphrase)
    }

    @discardableResult
    func restoreVersion(recordName: String, passphrase: String?) async throws -> RestoreReceipt {
        try await requireCloudAccess()
        return try await enabledManager.restoreVersion(recordName: recordName, passphrase: passphrase)
    }

    func listBackupVersions() async -> [BackupVersionInfo] {
        guard await isCloudAccessAllowed else { return [] }
        return await enabledManager.listBackupVersions()
    }

    /// Форвардим явно: дефолт протокола потерял бы причину отказа облака.
    func lookupBackupVersions() async -> BackupLookupOutcome {
        // Не `.empty`: «копий нет» и «мы намеренно не спрашивали» — разные состояния для UI.
        guard await isCloudAccessAllowed else { return .failed(.requiresSignIn) }
        return await enabledManager.lookupBackupVersions()
    }

    func deleteBackupVersion(recordName: String) async throws {
        try await requireCloudAccess()
        try await enabledManager.deleteBackupVersion(recordName: recordName)
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        // Информация о backup нужна и при выключенном автобэкапе (экран восстановления),
        // но не гостю: дата чужой копии — это уже утечка факта её существования (R10).
        guard await isCloudAccessAllowed else { return nil }
        return await enabledManager.lastBackupInfo()
    }
}
