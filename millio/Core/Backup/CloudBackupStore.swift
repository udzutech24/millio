//
//  CloudBackupStore.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import CloudKit
import OSLog

protocol CloudBackupContainerProtocol {
    var privateCloudDatabase: CloudBackupDatabaseProtocol { get }
    func accountStatus() async throws -> CKAccountStatus
}

protocol CloudBackupDatabaseProtocol {
    func record(for recordID: CKRecord.ID) async throws -> CKRecord
    func save(_ record: CKRecord) async throws -> CKRecord
    func deleteRecord(withID recordID: CKRecord.ID) async throws
}

struct CKContainerAdapter: CloudBackupContainerProtocol {
    private let container: CKContainer
    
    init(container: CKContainer) {
        self.container = container
    }
    
    var privateCloudDatabase: CloudBackupDatabaseProtocol {
        CKDatabaseAdapter(database: container.privateCloudDatabase)
    }
    
    func accountStatus() async throws -> CKAccountStatus {
        try await container.accountStatus()
    }
}

struct CKDatabaseAdapter: CloudBackupDatabaseProtocol {
    private let database: CKDatabase
    
    init(database: CKDatabase) {
        self.database = database
    }
    
    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        try await database.record(for: recordID)
    }
    
    func save(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }
}

protocol CloudBackupStoreProtocol {
    func isAvailable() async -> Bool
    func uploadBackup(_ data: Data, isPinned: Bool) async throws
    func downloadLatestBackup() async throws -> Data?
    func listBackupRecordNamesForRestore() async throws -> [String]
    func downloadBackup(recordName: String) async throws -> Data?
    func getLatestBackupInfo() async throws -> BackupInfo?
    func listBackupVersions() async throws -> [BackupVersionInfo]
    func deleteBackup(recordName: String) async throws
}

final class CloudBackupStore: CloudBackupStoreProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "CloudBackupStore")
    private let container: CloudBackupContainerProtocol
    private let snapshotRecordType = "AppBackup"
    private let legacyLatestRecordID = CKRecord.ID(recordName: "latest_backup")
    private let indexRecordType = "AppBackupIndex"
    private let indexRecordID = CKRecord.ID(recordName: "backup_index")
    private let indexEntriesField = "entriesJSON"
    private let maxSnapshots: Int
    private let now: () -> Date

    private struct BackupIndexEntry: Codable {
        let recordName: String
        let date: Date
        let size: Int64
        let version: String
        let isPinned: Bool

        init(recordName: String, date: Date, size: Int64, version: String, isPinned: Bool) {
            self.recordName = recordName
            self.date = date
            self.size = size
            self.version = version
            self.isPinned = isPinned
        }

        enum CodingKeys: String, CodingKey {
            case recordName
            case date
            case size
            case version
            case isPinned
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            recordName = try container.decode(String.self, forKey: .recordName)
            date = try container.decode(Date.self, forKey: .date)
            size = try container.decode(Int64.self, forKey: .size)
            version = try container.decode(String.self, forKey: .version)
            isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        }
    }
    
    init(
        container: CKContainer = .default(),
        maxSnapshots: Int = 3,
        now: @escaping () -> Date = Date.init
    ) {
        self.container = CKContainerAdapter(container: container)
        self.maxSnapshots = max(1, maxSnapshots)
        self.now = now
    }
    
    init(
        container: CloudBackupContainerProtocol,
        maxSnapshots: Int = 3,
        now: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.maxSnapshots = max(1, maxSnapshots)
        self.now = now
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
    
    func uploadBackup(_ data: Data, isPinned: Bool) async throws {
        let privateDB = container.privateCloudDatabase
        let backupDate = now()
        let backupVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        
        // Создаём временный файл для CKAsset
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        
        let snapshotRecordID = CKRecord.ID(recordName: makeSnapshotRecordName(on: backupDate))
        let snapshotRecord = CKRecord(recordType: snapshotRecordType, recordID: snapshotRecordID)
        snapshotRecord["backupData"] = CKAsset(fileURL: tempURL)
        snapshotRecord["backupDate"] = backupDate
        snapshotRecord["backupVersion"] = backupVersion
        snapshotRecord["backupSize"] = Int64(data.count)
        _ = try await privateDB.save(snapshotRecord)

        var entries = try await loadIndexEntries(from: privateDB)
        entries.removeAll { $0.recordName == snapshotRecordID.recordName }
        entries.insert(
            BackupIndexEntry(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: isPinned
            ),
            at: 0
        )

        let pinnedEntries = entries.filter(\.isPinned)
        let rollingEntries = entries.filter { !$0.isPinned }
        let staleEntries = Array(rollingEntries.dropFirst(maxSnapshots))
        entries = pinnedEntries + Array(rollingEntries.prefix(maxSnapshots))
        entries.sort { $0.date > $1.date }
        try await saveIndexEntries(entries, to: privateDB)

        for stale in staleEntries {
            do {
                try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: stale.recordName))
            } catch {
                logger.warning("Failed to delete stale snapshot '\(stale.recordName, privacy: .public)': \(error.localizedDescription)")
            }
        }

        do {
            try await saveLegacyLatestRecord(
                dataSize: Int64(data.count),
                backupDate: backupDate,
                backupVersion: backupVersion,
                assetURL: tempURL,
                database: privateDB
            )
        } catch {
            // Legacy latest используется только как fallback/совместимость.
            logger.warning("Failed to update legacy latest backup record: \(error.localizedDescription)")
        }
        
        logger.info("Backup uploaded successfully")
    }
    
    func downloadLatestBackup() async throws -> Data? {
        let candidates = try await listBackupRecordNamesForRestore()

        for recordName in candidates {
            if let data = try await downloadBackup(recordName: recordName) {
                logger.info("Backup downloaded successfully, recordName: \(recordName, privacy: .public), size: \(data.count) bytes")
                return data
            }
        }

        logger.info("No backup found in iCloud")
        return nil
    }

    func listBackupRecordNamesForRestore() async throws -> [String] {
        let privateDB = container.privateCloudDatabase
        let entries = try await loadIndexEntries(from: privateDB)

        var orderedNames: [String] = []
        var seen = Set<String>()

        for entry in entries {
            if seen.insert(entry.recordName).inserted {
                orderedNames.append(entry.recordName)
            }
        }

        let legacyName = legacyLatestRecordID.recordName
        if seen.insert(legacyName).inserted {
            orderedNames.append(legacyName)
        }

        return orderedNames
    }

    func downloadBackup(recordName: String) async throws -> Data? {
        let privateDB = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: recordName)
        do {
            let record = try await privateDB.record(for: recordID)
            return try await readBackupData(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }
    }
    
    func getLatestBackupInfo() async throws -> BackupInfo? {
        let privateDB = container.privateCloudDatabase

        if let info = try await latestInfoFromIndex(using: privateDB) {
            return info
        }

        if let info = try await legacyLatestInfo(using: privateDB) {
            return info
        }

        return nil
    }

    func listBackupVersions() async throws -> [BackupVersionInfo] {
        let privateDB = container.privateCloudDatabase
        let entries = try await loadIndexEntries(from: privateDB).sorted { $0.date > $1.date }
        if !entries.isEmpty {
            return entries.map {
                BackupVersionInfo(
                    recordName: $0.recordName,
                    date: $0.date,
                    size: $0.size,
                    version: $0.version,
                    isPinned: $0.isPinned
                )
            }
        }

        if let legacy = try await legacyLatestInfo(using: privateDB) {
            return [
                BackupVersionInfo(
                    recordName: legacyLatestRecordID.recordName,
                    date: legacy.date,
                    size: legacy.size,
                    version: legacy.version,
                    isPinned: false
                )
            ]
        }
        return []
    }

    func deleteBackup(recordName: String) async throws {
        let privateDB = container.privateCloudDatabase
        do {
            try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: recordName))
        } catch let error as CKError where error.code == .unknownItem {
            // Запись уже отсутствует — удаляем только из индекса.
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }

        var entries = try await loadIndexEntries(from: privateDB)
        let initialCount = entries.count
        entries.removeAll { $0.recordName == recordName }
        if entries.count != initialCount {
            try await saveIndexEntries(entries, to: privateDB)
        }
    }

    private func makeSnapshotRecordName(on date: Date) -> String {
        "snapshot_\(Int(date.timeIntervalSince1970 * 1000))_\(UUID().uuidString)"
    }

    private func saveLegacyLatestRecord(
        dataSize: Int64,
        backupDate: Date,
        backupVersion: String,
        assetURL: URL,
        database: CloudBackupDatabaseProtocol
    ) async throws {
        let legacyRecord: CKRecord
        do {
            legacyRecord = try await database.record(for: legacyLatestRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            legacyRecord = CKRecord(recordType: snapshotRecordType, recordID: legacyLatestRecordID)
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }

        legacyRecord["backupData"] = CKAsset(fileURL: assetURL)
        legacyRecord["backupDate"] = backupDate
        legacyRecord["backupVersion"] = backupVersion
        legacyRecord["backupSize"] = dataSize
        _ = try await database.save(legacyRecord)
    }

    private func loadIndexEntries(from database: CloudBackupDatabaseProtocol) async throws -> [BackupIndexEntry] {
        do {
            let indexRecord = try await database.record(for: indexRecordID)
            guard let raw = indexRecord[indexEntriesField] as? String else {
                return []
            }
            guard let data = raw.data(using: .utf8) else {
                return []
            }
            return (try? JSONDecoder().decode([BackupIndexEntry].self, from: data)) ?? []
        } catch let error as CKError where error.code == .unknownItem {
            return []
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }
    }

    private func saveIndexEntries(_ entries: [BackupIndexEntry], to database: CloudBackupDatabaseProtocol) async throws {
        let indexRecord: CKRecord
        do {
            indexRecord = try await database.record(for: indexRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            indexRecord = CKRecord(recordType: indexRecordType, recordID: indexRecordID)
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }

        let encoded = try JSONEncoder().encode(entries)
        indexRecord[indexEntriesField] = String(decoding: encoded, as: UTF8.self)
        indexRecord["updatedAt"] = now()
        _ = try await database.save(indexRecord)
    }

    private func readBackupData(from record: CKRecord) async throws -> Data? {
        guard let asset = record["backupData"] as? CKAsset else {
            return nil
        }

        guard let fileURL = asset.fileURL else {
            return nil
        }

        return try await Task.detached(priority: .utility) {
            try Data(contentsOf: fileURL)
        }.value
    }

    private func latestInfoFromIndex(using database: CloudBackupDatabaseProtocol) async throws -> BackupInfo? {
        let entries = try await loadIndexEntries(from: database)
        guard !entries.isEmpty else { return nil }

        for entry in entries {
            do {
                let snapshotRecord = try await database.record(for: CKRecord.ID(recordName: entry.recordName))
                if let info = backupInfo(from: snapshotRecord) {
                    return info
                }
                return BackupInfo(date: entry.date, size: entry.size, version: entry.version)
            } catch let error as CKError where error.code == .unknownItem {
                continue
            } catch {
                throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
            }
        }

        return nil
    }

    private func legacyLatestInfo(using database: CloudBackupDatabaseProtocol) async throws -> BackupInfo? {
        do {
            let record = try await database.record(for: legacyLatestRecordID)
            return backupInfo(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
        }
    }

    private func backupInfo(from record: CKRecord) -> BackupInfo? {
        guard let date = record["backupDate"] as? Date,
              let size = record["backupSize"] as? Int64,
              let version = record["backupVersion"] as? String else {
            return nil
        }
        return BackupInfo(date: date, size: size, version: version)
    }
}
