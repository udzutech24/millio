//
//  BackupManager.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import OSLog
import Compression

protocol BackupManagerProtocol {
    func isAvailable() async -> Bool
    func backupNow() async throws
    func restoreLatest() async throws
    func lastBackupInfo() async -> BackupInfo?
}

nonisolated final class BackupManager: BackupManagerProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "BackupManager")
    private let cloudStore: CloudBackupStoreProtocol
    private let dataRepository: DataRepositoryProtocol
    private let encryption: BackupEncryptionProtocol?
    private var backupTask: Task<Void, Never>?
    
    nonisolated init(
        cloudStore: CloudBackupStoreProtocol,
        dataRepository: DataRepositoryProtocol,
        encryption: BackupEncryptionProtocol? = nil
    ) {
        self.cloudStore = cloudStore
        self.dataRepository = dataRepository
        self.encryption = encryption
    }
    
    convenience init(dataRepository: DataRepositoryProtocol) {
        // Проверяем настройки шифрования синхронно
        let isEncryptionEnabled = SettingsManager.shared.isEncryptionEnabled
        let encryption: BackupEncryptionProtocol? = isEncryptionEnabled
            ? KeychainBackupEncryption()
            : nil
        self.init(cloudStore: CloudBackupStore(), dataRepository: dataRepository, encryption: encryption)
    }
    
    func isAvailable() async -> Bool {
        await cloudStore.isAvailable()
    }
    
    func backupNow() async throws {
        logger.info("Starting backup...")
        
        let dataRepository = self.dataRepository
        let encryption = self.encryption
        let cloudStore = self.cloudStore
        
        try await withRetry(policy: .default) {
            guard await self.isAvailable() else {
                throw AppError.iCloudUnavailable
            }
            
            var backupData = try dataRepository.exportAllData()
            
            // Сжимаем backup
            backupData = try self.compress(backupData)
            
            // Шифруем если включено
            if let encryption = encryption {
                backupData = try encryption.encrypt(backupData)
            }
            
            try await cloudStore.uploadBackup(backupData)
        }
        
        logger.info("Backup completed successfully")
    }
    
    private func compress(_ data: Data) throws -> Data {
        // Используем Compression framework для сжатия
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { buffer.deallocate() }
        
        data.copyBytes(to: buffer, count: data.count)
        
        let compressedSize = data.count + (data.count / 16) + 64
        let compressed = UnsafeMutablePointer<UInt8>.allocate(capacity: compressedSize)
        defer { compressed.deallocate() }
        
        let result = compression_encode_buffer(
            compressed, compressedSize,
            buffer, data.count,
            nil,
            COMPRESSION_LZFSE
        )
        
        guard result > 0 else {
            // Если сжатие не удалось, возвращаем исходные данные
            return data
        }
        
        return Data(bytes: compressed, count: result)
    }
    
    func restoreLatest() async throws {
        logger.info("Starting restore...")
        
        let dataRepository = self.dataRepository
        let encryption = self.encryption
        let cloudStore = self.cloudStore
        
        try await withRetry(policy: .default) {
            guard await self.isAvailable() else {
                throw AppError.iCloudUnavailable
            }
            
            guard var backupData = try await cloudStore.downloadLatestBackup() else {
                throw AppError.restoreFailed("Backup не найден в iCloud")
            }
            
            // Расшифровываем если было зашифровано
            if let encryption = encryption {
                backupData = try encryption.decrypt(backupData)
            }
            
            // Распаковываем backup
            backupData = try self.decompress(backupData)
            
            // Очищаем локальные данные
            try dataRepository.clearAllData()
            
            // Импортируем данные из backup
            try dataRepository.importAllData(backupData)
        }
        
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
    
    private func decompress(_ data: Data) throws -> Data {
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { buffer.deallocate() }
        
        data.copyBytes(to: buffer, count: data.count)
        
        // Пытаемся определить размер распакованных данных (упрощенно - используем 10x)
        let decompressedSize = data.count * 10
        let decompressed = UnsafeMutablePointer<UInt8>.allocate(capacity: decompressedSize)
        defer { decompressed.deallocate() }
        
        let result = compression_decode_buffer(
            decompressed, decompressedSize,
            buffer, data.count,
            nil,
            COMPRESSION_LZFSE
        )
        
        guard result > 0 else {
            // Если распаковка не удалась, возможно данные не сжаты
            return data
        }
        
        return Data(bytes: decompressed, count: result)
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
