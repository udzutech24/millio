//
//  BackupManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog

protocol BackupManagerProtocol {
    func isAvailable() async -> Bool
    func backupNow() async throws
    func restoreLatest() async throws
    func lastBackupInfo() async -> BackupInfo?
}

nonisolated(unsafe) final class BackupManager: BackupManagerProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "BackupManager")
    private let cloudStore: CloudBackupStoreProtocol
    private let dataRepository: DataRepositoryProtocol
    private var backupTask: Task<Void, Never>?
    
    nonisolated init(
        cloudStore: CloudBackupStoreProtocol = CloudBackupStore(),
        dataRepository: DataRepositoryProtocol
    ) {
        self.cloudStore = cloudStore
        self.dataRepository = dataRepository
    }
    
    func isAvailable() async -> Bool {
        await cloudStore.isAvailable()
    }
    
    func backupNow() async throws {
        logger.info("Starting backup...")
        
        guard await isAvailable() else {
            throw AppError.iCloudUnavailable
        }
        
        let backupData = try dataRepository.exportAllData()
        try await cloudStore.uploadBackup(backupData)
        
        logger.info("Backup completed successfully")
    }
    
    func restoreLatest() async throws {
        logger.info("Starting restore...")
        
        guard await isAvailable() else {
            throw AppError.iCloudUnavailable
        }
        
        guard let backupData = try await cloudStore.downloadLatestBackup() else {
            throw AppError.restoreFailed("Backup не найден в iCloud")
        }
        
        // Очищаем локальные данные
        try dataRepository.clearAllData()
        
        // Импортируем данные из backup
        try dataRepository.importAllData(backupData)
        
        logger.info("Restore completed successfully")
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        do {
            return try await cloudStore.getLatestBackupInfo()
        } catch {
            logger.error("Failed to get backup info: \(error.localizedDescription)")
            return nil
        }
    }
    
    func scheduleBackup() {
        backupTask?.cancel()
        backupTask = Task {
            do {
                try await Task.sleep(for: .seconds(5)) // Debounce
                try await backupNow()
            } catch {
                logger.error("Scheduled backup failed: \(error.localizedDescription)")
            }
        }
    }
}
