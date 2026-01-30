//
//  CloudBackupStore.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import CloudKit
import OSLog

protocol CloudBackupStoreProtocol {
    func isAvailable() async -> Bool
    func uploadBackup(_ data: Data) async throws
    func downloadLatestBackup() async throws -> Data?
    func getLatestBackupInfo() async throws -> BackupInfo?
}

nonisolated final class CloudBackupStore: CloudBackupStoreProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "CloudBackupStore")
    private let container: CKContainer
    private let recordType = "AppBackup"
    private let recordID = CKRecord.ID(recordName: "latest_backup")
    
    nonisolated init(container: CKContainer = .default()) {
        self.container = container
    }
    
    func isAvailable() async -> Bool {
        do {
            let status = try await container.accountStatus()
            return status == .available
        } catch {
            logger.error("Failed to check iCloud availability: \(error.localizedDescription)")
            return false
        }
    }
    
    func uploadBackup(_ data: Data) async throws {
        let privateDB = container.privateCloudDatabase
        
        // Создаём временный файл для CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let asset = CKAsset(fileURL: tempURL)
        let record: CKRecord
        do {
            record = try await privateDB.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            record = CKRecord(recordType: recordType, recordID: recordID)
        } catch {
            throw AppError.backupFailed(error.localizedDescription)
        }
        record["backupData"] = asset
        record["backupDate"] = Date()
        record["backupVersion"] = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        record["backupSize"] = Int64(data.count)
        
        try await privateDB.save(record)
        logger.info("Backup uploaded successfully")
    }
    
    func downloadLatestBackup() async throws -> Data? {
        let privateDB = container.privateCloudDatabase
        
        do {
            let record = try await privateDB.record(for: recordID)
            
            guard let asset = record["backupData"] as? CKAsset else {
                logger.warning("No backup asset found in record")
                return nil
            }
            
            guard let fileURL = asset.fileURL else {
                throw AppError.backupCorrupted
            }
            
            let data = try Data(contentsOf: fileURL)
            logger.info("Backup downloaded successfully, size: \(data.count) bytes")
            return data
            
        } catch let error as CKError {
            if error.code == .unknownItem {
                logger.info("No backup found in iCloud")
                return nil
            }
            throw AppError.backupFailed(error.localizedDescription)
        } catch {
            throw AppError.backupFailed(error.localizedDescription)
        }
    }
    
    func getLatestBackupInfo() async throws -> BackupInfo? {
        let privateDB = container.privateCloudDatabase
        
        do {
            let record = try await privateDB.record(for: recordID)
            
            guard let date = record["backupDate"] as? Date,
                  let size = record["backupSize"] as? Int64,
                  let version = record["backupVersion"] as? String else {
                return nil
            }
            
            return BackupInfo(date: date, size: size, version: version)
            
        } catch let error as CKError {
            if error.code == .unknownItem {
                return nil
            }
            throw AppError.backupFailed(error.localizedDescription)
        } catch {
            throw AppError.backupFailed(error.localizedDescription)
        }
    }
}
