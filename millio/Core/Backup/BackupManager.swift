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
    func backupNow(passphrase: String?) async throws
    func restoreLatest() async throws
    func restoreLatest(passphrase: String?) async throws
    func lastBackupInfo() async -> BackupInfo?
}

actor BackupManager: BackupManagerProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "BackupManager")
    private let cloudStore: CloudBackupStoreProtocol
    private let dataRepository: DataRepositoryProtocol
    private let encryption: BackupEncryptionProtocol?
    private var backupTask: Task<Void, Never>?
    
    init(
        cloudStore: CloudBackupStoreProtocol,
        dataRepository: DataRepositoryProtocol,
        encryption: BackupEncryptionProtocol? = nil
    ) {
        self.cloudStore = cloudStore
        self.dataRepository = dataRepository
        self.encryption = encryption
    }
    
    init(dataRepository: DataRepositoryProtocol) {
        // Проверяем настройки шифрования синхронно
        let isEncryptionEnabled = SettingsManager.shared.isEncryptionEnabled
        let encryption: BackupEncryptionProtocol? = isEncryptionEnabled
            ? KeychainBackupEncryption()
            : nil
        self.cloudStore = CloudBackupStore()
        self.dataRepository = dataRepository
        self.encryption = encryption
    }
    
    func isAvailable() async -> Bool {
        await cloudStore.isAvailable()
    }
    
    func backupNow() async throws {
        try await backupNow(passphrase: nil)
    }
    
    func backupNow(passphrase: String?) async throws {
        logger.info("Starting backup...")
        
        let dataRepository = self.dataRepository
        let encryption = self.encryption
        let cloudStore = self.cloudStore

        CrashReporting.setCustomValue("backup", forKey: "backup_operation")
        CrashReporting.setCustomValue(passphrase != nil ? "passphrase" : (encryption != nil ? "keychain" : "none"), forKey: "backup_encryption_mode")
        
        do {
            try await withRetry(
                policy: .default,
                shouldRetry: { error in
                    guard let appError = error as? AppError else { return true }
                    switch appError {
                    case .iCloudUnavailable, .backupCorrupted, .incompatibleSchemaVersion:
                        return false
                    case .restoreFailed:
                        return false
                    default:
                        return true
                    }
                }
            ) {
                guard await self.isAvailable() else {
                    throw AppError.iCloudUnavailable
                }
                
                var payload = try await dataRepository.exportAllDataAsync()
                let metadata: BackupMetadata = {
                    do {
                        guard let json = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
                              let metadataDict = json["metadata"] as? [String: Any] else {
                            return BackupMetadata()
                        }
                        let data = try JSONSerialization.data(withJSONObject: metadataDict)
                        return try JSONDecoder().decode(BackupMetadata.self, from: data)
                    } catch {
                        return BackupMetadata()
                    }
                }()
                
                var compressionInfo: BackupCompressionInfo? = nil
                let compressed = try self.compressLZFSE(payload)
                if compressed.count < payload.count {
                    compressionInfo = BackupCompressionInfo(
                        algorithm: "lzfse",
                        originalSize: payload.count
                    )
                    payload = compressed
                }
                
                var encryptionInfo: BackupEncryptionInfo? = nil
                if let passphrase {
                    let (encrypted, kdf) = try PassphraseBackupEncryption.encrypt(payload, passphrase: passphrase)
                    payload = encrypted
                    encryptionInfo = BackupEncryptionInfo(algorithm: "aesgcm-passphrase", kdf: kdf)
                } else if let encryption {
                    payload = try encryption.encrypt(payload)
                    encryptionInfo = BackupEncryptionInfo(algorithm: "aesgcm-keychain", kdf: nil)
                }
                
                let header = BackupEnvelopeHeader(
                    formatVersion: BackupEnvelopeHeader.currentFormatVersion,
                    metadata: metadata,
                    compression: compressionInfo,
                    encryption: encryptionInfo
                )
                
                let packed = try BackupEnvelope.pack(header: header, payload: payload)
                try await cloudStore.uploadBackup(packed)
            }
            
            logger.info("Backup completed successfully")
        } catch {
            CrashReporting.log("Backup failed: \(String(describing: error))")
            CrashReporting.record(error: error)
            throw error
        }
    }
    
    private func compressLZFSE(_ data: Data) throws -> Data {
        try processCompressionStream(data, operation: COMPRESSION_STREAM_ENCODE)
    }
    
    func restoreLatest() async throws {
        try await restoreLatest(passphrase: nil)
    }
    
    func restoreLatest(passphrase: String?) async throws {
        logger.info("Starting restore...")
        
        let dataRepository = self.dataRepository
        let encryption = self.encryption
        let cloudStore = self.cloudStore

        CrashReporting.setCustomValue("restore", forKey: "backup_operation")
        CrashReporting.setCustomValue(passphrase != nil ? "passphrase" : (encryption != nil ? "keychain" : "none"), forKey: "backup_encryption_mode")
        
        do {
            try await withRetry(
                policy: .default,
                shouldRetry: { error in
                    guard let appError = error as? AppError else { return true }
                    switch appError {
                    case .iCloudUnavailable, .backupCorrupted, .incompatibleSchemaVersion:
                        return false
                    case .restoreFailed:
                        return false
                    default:
                        return true
                    }
                }
            ) {
            guard await self.isAvailable() else {
                throw AppError.iCloudUnavailable
            }
            
            guard let downloadedData = try await cloudStore.downloadLatestBackup() else {
                throw AppError.restoreFailed("Backup не найден в iCloud")
            }
            
            var backupData: Data
            
            if self.looksLikeEnvelope(downloadedData) {
                let (header, payload): (BackupEnvelopeHeader, Data)
                do {
                    (header, payload) = try BackupEnvelope.unpack(downloadedData)
                } catch {
                    throw AppError.backupCorrupted
                }
                guard header.formatVersion == BackupEnvelopeHeader.currentFormatVersion else {
                    throw AppError.incompatibleSchemaVersion
                }
                
                backupData = payload
                
                if let encryptionInfo = header.encryption {
                    switch encryptionInfo.algorithm {
                    case "aesgcm-passphrase":
                        guard let passphrase else {
                            throw AppError.restoreFailed("Backup зашифрован парольной фразой. Введите парольную фразу и повторите.")
                        }
                        guard let kdf = encryptionInfo.kdf else {
                            throw AppError.backupCorrupted
                        }
                        backupData = try PassphraseBackupEncryption.decrypt(backupData, passphrase: passphrase, kdf: kdf)
                    case "aesgcm-keychain":
                        let decryptor = encryption ?? KeychainBackupEncryption()
                        do {
                            backupData = try decryptor.decrypt(backupData)
                        } catch {
                            throw AppError.restoreFailed("Backup зашифрован и не может быть расшифрован на этом устройстве")
                        }
                    default:
                        throw AppError.backupCorrupted
                    }
                }
                
                if let compression = header.compression {
                    guard compression.algorithm == "lzfse" else {
                        throw AppError.backupCorrupted
                    }
                    backupData = try self.decompressLZFSE(backupData)
                    if backupData.count != compression.originalSize {
                        throw AppError.backupCorrupted
                    }
                }
            } else {
                backupData = downloadedData
                
                if let encryption {
                    do {
                        backupData = try encryption.decrypt(backupData)
                    } catch {
                        throw AppError.restoreFailed("Не удалось расшифровать backup")
                    }
                }
                
                backupData = self.decompressLZFSEIfNeeded(backupData)
            }
            
            let previousData = try await dataRepository.exportAllDataAsync()
            let snapshotURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("millio-pre-restore-\(UUID().uuidString).json")
            do {
                try previousData.write(to: snapshotURL, options: .atomic)
            } catch {
                throw AppError.restoreFailed("Не удалось создать снимок данных перед восстановлением")
            }
            
            do {
                try await dataRepository.clearAllDataAsync()
                try await dataRepository.importAllDataAsync(backupData)
                try? FileManager.default.removeItem(at: snapshotURL)
            } catch {
                do {
                    try await dataRepository.clearAllDataAsync()
                    let snapshotData = try Data(contentsOf: snapshotURL)
                    try await dataRepository.importAllDataAsync(snapshotData)
                    try? FileManager.default.removeItem(at: snapshotURL)
                } catch {
                    throw AppError.restoreFailed("Не удалось восстановить данные после ошибки восстановления")
                }
                
                throw error
            }
        }
        
            logger.info("Restore completed successfully")
        } catch {
            CrashReporting.log("Restore failed: \(String(describing: error))")
            CrashReporting.record(error: error)
            throw error
        }
    }

    private func looksLikeEnvelope(_ data: Data) -> Bool {
        guard data.count >= 5 else { return false }
        let headerLength: Int = data.prefix(4).withUnsafeBytes { rawBufferPointer in
            let value = rawBufferPointer.load(as: UInt32.self)
            return Int(UInt32(bigEndian: value))
        }
        guard headerLength > 1, headerLength <= data.count - 4 else { return false }
        let headerStartIndex = data.index(data.startIndex, offsetBy: 4)
        let firstHeaderByte = data[headerStartIndex]
        return firstHeaderByte == UInt8(ascii: "{")
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        do {
            return try await cloudStore.getLatestBackupInfo()
        } catch {
            logger.error("Failed to get backup info: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func decompressLZFSE(_ data: Data) throws -> Data {
        try processCompressionStream(data, operation: COMPRESSION_STREAM_DECODE)
    }
    
    private func decompressLZFSEIfNeeded(_ data: Data) -> Data {
        (try? decompressLZFSE(data)) ?? data
    }
    
    private func processCompressionStream(_ data: Data, operation: compression_stream_operation) throws -> Data {
        let dummyPointer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { dummyPointer.deallocate() }
        
        var stream = compression_stream(
            dst_ptr: dummyPointer,
            dst_size: 0,
            src_ptr: UnsafePointer(dummyPointer),
            src_size: 0,
            state: nil
        )
        let status = compression_stream_init(&stream, operation, COMPRESSION_LZFSE)
        guard status != COMPRESSION_STATUS_ERROR else {
            throw AppError.backupFailed("Ошибка инициализации сжатия")
        }
        defer { compression_stream_destroy(&stream) }
        
        let dstSize = 64 * 1024
        let dstBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: dstSize)
        defer { dstBuffer.deallocate() }
        
        return try data.withUnsafeBytes { rawBufferPointer in
            guard let srcBaseAddress = rawBufferPointer.bindMemory(to: UInt8.self).baseAddress else {
                return Data()
            }
            
            stream.src_ptr = srcBaseAddress
            stream.src_size = data.count
            
            var output = Data()
            
            while true {
                stream.dst_ptr = dstBuffer
                stream.dst_size = dstSize
                
                let flags: Int32
                if operation == COMPRESSION_STREAM_ENCODE && stream.src_size == 0 {
                    flags = Int32(COMPRESSION_STREAM_FINALIZE.rawValue)
                } else {
                    flags = 0
                }
                
                let processStatus = compression_stream_process(&stream, flags)
                let produced = dstSize - stream.dst_size
                if produced > 0 {
                    output.append(dstBuffer, count: produced)
                }
                
                switch processStatus {
                case COMPRESSION_STATUS_OK:
                    continue
                case COMPRESSION_STATUS_END:
                    return output
                default:
                    if operation == COMPRESSION_STREAM_ENCODE {
                        throw AppError.backupFailed("Не удалось сжать backup")
                    } else {
                        throw AppError.backupCorrupted
                    }
                }
            }
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
