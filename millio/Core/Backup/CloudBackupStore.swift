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
    func records(recordType: String) async throws -> [CKRecord]
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

    func records(recordType: String) async throws -> [CKRecord] {
        try await fetchRecords(matching: CKQuery(recordType: recordType, predicate: NSPredicate(value: true)))
    }
    
    func save(_ record: CKRecord) async throws -> CKRecord {
        try await database.save(record)
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }

    private func fetchRecords(matching query: CKQuery) async throws -> [CKRecord] {
        var records: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let page = try await fetchQueryPage(query: cursor == nil ? query : nil, cursor: cursor)
            records.append(contentsOf: page.records)
            cursor = page.cursor
        } while cursor != nil

        return records
    }

    private func fetchQueryPage(
        query: CKQuery?,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> (records: [CKRecord], cursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            let operation: CKQueryOperation
            if let cursor {
                operation = CKQueryOperation(cursor: cursor)
            } else if let query {
                operation = CKQueryOperation(query: query)
            } else {
                continuation.resume(throwing: BackupFailureCode.cloudKitOperationFailed("Invalid query state").appError)
                return
            }

            var fetchedRecords: [CKRecord] = []
            var firstError: Error?
            var didResume = false

            func resumeOnce(with result: Result<(records: [CKRecord], cursor: CKQueryOperation.Cursor?), Error>) {
                guard !didResume else { return }
                didResume = true
                continuation.resume(with: result)
            }

            operation.recordMatchedBlock = { _, result in
                switch result {
                case .success(let record):
                    fetchedRecords.append(record)
                case .failure(let error):
                    if firstError == nil {
                        firstError = error
                    }
                }
            }

            operation.queryResultBlock = { result in
                if let firstError {
                    resumeOnce(with: .failure(firstError))
                    return
                }

                switch result {
                case .success(let nextCursor):
                    resumeOnce(with: .success((records: fetchedRecords, cursor: nextCursor)))
                case .failure(let error):
                    resumeOnce(with: .failure(error))
                }
            }

            database.add(operation)
        }
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
    private let snapshotDateField = "backupDate"
    private let snapshotVersionField = "backupVersion"
    private let snapshotSizeField = "backupSize"
    private let snapshotPinnedField = "isPinned"
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
        
        do {
            let snapshotRecordID = CKRecord.ID(recordName: makeSnapshotRecordName(on: backupDate))
            let snapshotRecord = CKRecord(recordType: snapshotRecordType, recordID: snapshotRecordID)
            snapshotRecord["backupData"] = CKAsset(fileURL: tempURL)
            snapshotRecord[snapshotDateField] = backupDate
            snapshotRecord[snapshotVersionField] = backupVersion
            snapshotRecord[snapshotSizeField] = Int64(data.count)
            snapshotRecord[snapshotPinnedField] = isPinned ? 1 : 0
            _ = try await privateDB.save(snapshotRecord)

            let newEntry = BackupIndexEntry(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: isPinned
            )
            let existingEntries = try await loadIndexEntries(from: privateDB)
            let indexUpdate = mergeIndexEntries(existingEntries, appending: newEntry)

            for stale in indexUpdate.staleEntries {
                do {
                    try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: stale.recordName))
                } catch {
                    logger.warning("Failed to delete stale snapshot '\(stale.recordName, privacy: .public)': \(self.descriptiveCloudKitError(error), privacy: .public)")
                }
            }

            do {
                try await saveIndexEntries(indexUpdate.retainedEntries, to: privateDB)
            } catch {
                logger.warning("Failed to save backup index cache: \(self.descriptiveCloudKitError(error), privacy: .public)")
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
                logger.warning("Failed to update legacy latest backup record: \(self.descriptiveCloudKitError(error), privacy: .public)")
            }
        } catch {
            throw mapCloudKitError(error)
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
        let versions = try await listSnapshotVersions(using: privateDB)

        var orderedNames: [String] = []
        var seen = Set<String>()

        for version in versions {
            if seen.insert(version.recordName).inserted {
                orderedNames.append(version.recordName)
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
            throw mapCloudKitError(error)
        }
    }
    
    func getLatestBackupInfo() async throws -> BackupInfo? {
        let privateDB = container.privateCloudDatabase

        if let info = try await latestInfoFromSnapshots(using: privateDB) {
            return info
        }

        if let info = try await legacyLatestInfo(using: privateDB) {
            return info
        }

        return nil
    }

    func listBackupVersions() async throws -> [BackupVersionInfo] {
        let privateDB = container.privateCloudDatabase
        let versions = try await listSnapshotVersions(using: privateDB)
        if !versions.isEmpty {
            return versions
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
            throw mapCloudKitError(error)
        }

        do {
            let currentEntries = try await loadIndexEntries(from: privateDB)
            let filteredEntries = currentEntries.filter { $0.recordName != recordName }
            try await saveIndexEntries(filteredEntries, to: privateDB)
        } catch {
            logger.warning("Failed to update backup index cache after delete: \(self.descriptiveCloudKitError(error), privacy: .public)")
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
            throw mapCloudKitError(error)
        }

        legacyRecord["backupData"] = CKAsset(fileURL: assetURL)
        legacyRecord[snapshotDateField] = backupDate
        legacyRecord[snapshotVersionField] = backupVersion
        legacyRecord[snapshotSizeField] = dataSize
        do {
            _ = try await database.save(legacyRecord)
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func listSnapshotVersions(using database: CloudBackupDatabaseProtocol) async throws -> [BackupVersionInfo] {
        let indexEntries = try await loadIndexEntries(from: database)
        if !indexEntries.isEmpty {
            return indexEntries
                .map {
                    BackupVersionInfo(
                        recordName: $0.recordName,
                        date: $0.date,
                        size: $0.size,
                        version: $0.version,
                        isPinned: $0.isPinned
                    )
                }
                .sorted { $0.date > $1.date }
        }

        do {
            // Snapshot records are the source of truth. backup_index is only a best-effort cache.
            let records = try await database.records(recordType: snapshotRecordType)
            return records
                .filter { $0.recordID != legacyLatestRecordID }
                .compactMap(snapshotVersionInfo(from:))
                .sorted { $0.date > $1.date }
        } catch let error as CKError where error.code == .unknownItem {
            return []
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func mergeIndexEntries(
        _ existingEntries: [BackupIndexEntry],
        appending newEntry: BackupIndexEntry
    ) -> (retainedEntries: [BackupIndexEntry], staleEntries: [BackupIndexEntry]) {
        let dedupedEntries = [newEntry] + existingEntries.filter { $0.recordName != newEntry.recordName }
        let sortedEntries = dedupedEntries.sorted { $0.date > $1.date }

        let pinnedEntries = sortedEntries.filter(\.isPinned)
        let rollingEntries = sortedEntries.filter { !$0.isPinned }
        let retainedNames = Set(
            pinnedEntries.map(\.recordName) +
            rollingEntries.prefix(maxSnapshots).map(\.recordName)
        )

        let retainedEntries = sortedEntries.filter { retainedNames.contains($0.recordName) }
        let staleEntries = sortedEntries.filter {
            !$0.isPinned && !retainedNames.contains($0.recordName)
        }

        return (retainedEntries, staleEntries)
    }

    private func staleSnapshotEntries(from versions: [BackupVersionInfo]) -> [BackupVersionInfo] {
        let pinnedEntries = versions.filter(\.isPinned)
        let rollingEntries = versions.filter { !$0.isPinned }
        let retainedRecordNames = Set(
            pinnedEntries.map(\.recordName) +
            rollingEntries.prefix(maxSnapshots).map(\.recordName)
        )

        return versions.filter {
            !$0.isPinned && !retainedRecordNames.contains($0.recordName)
        }
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
            throw mapCloudKitError(error)
        }
    }

    private func saveIndexEntries(_ entries: [BackupIndexEntry], to database: CloudBackupDatabaseProtocol) async throws {
        let indexRecord: CKRecord
        do {
            indexRecord = try await database.record(for: indexRecordID)
        } catch let error as CKError where error.code == .unknownItem {
            indexRecord = CKRecord(recordType: indexRecordType, recordID: indexRecordID)
        } catch {
            throw mapCloudKitError(error)
        }

        let encoded = try JSONEncoder().encode(entries)
        indexRecord[indexEntriesField] = String(decoding: encoded, as: UTF8.self)
        indexRecord["updatedAt"] = now()
        do {
            _ = try await database.save(indexRecord)
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func syncIndexCacheBestEffort(using database: CloudBackupDatabaseProtocol) async {
        do {
            let entries = try await listSnapshotVersions(using: database).map {
                BackupIndexEntry(
                    recordName: $0.recordName,
                    date: $0.date,
                    size: $0.size,
                    version: $0.version,
                    isPinned: $0.isPinned
                )
            }
            try await saveIndexEntries(entries, to: database)
        } catch {
            logger.warning("Failed to sync backup index cache: \(self.descriptiveCloudKitError(error), privacy: .public)")
        }
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

    private func latestInfoFromSnapshots(using database: CloudBackupDatabaseProtocol) async throws -> BackupInfo? {
        try await listSnapshotVersions(using: database).first.map {
            BackupInfo(date: $0.date, size: $0.size, version: $0.version)
        }
    }

    private func legacyLatestInfo(using database: CloudBackupDatabaseProtocol) async throws -> BackupInfo? {
        do {
            let record = try await database.record(for: legacyLatestRecordID)
            return backupInfo(from: record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func mapCloudKitError(_ error: Error) -> Error {
        if let appError = error as? AppError {
            return appError
        }

        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain || error is CKError {
            return BackupFailureCode.cloudKitOperationFailed(descriptiveCloudKitError(error)).appError
        }

        return BackupFailureCode.cloudKitOperationFailed(error.localizedDescription).appError
    }

    private func descriptiveCloudKitError(_ error: Error) -> String {
        let nsError = error as NSError
        if let serverMessage = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String,
           !serverMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return serverMessage
        }

        return error.localizedDescription
    }

    private func backupInfo(from record: CKRecord) -> BackupInfo? {
        guard let date = record[snapshotDateField] as? Date,
              let size = record[snapshotSizeField] as? Int64,
              let version = record[snapshotVersionField] as? String else {
            return nil
        }
        return BackupInfo(date: date, size: size, version: version)
    }

    private func snapshotVersionInfo(from record: CKRecord) -> BackupVersionInfo? {
        guard let info = backupInfo(from: record) else {
            return nil
        }

        let isPinned: Bool
        if let value = record[snapshotPinnedField] as? Int64 {
            isPinned = value != 0
        } else if let value = record[snapshotPinnedField] as? NSNumber {
            isPinned = value.boolValue
        } else {
            isPinned = false
        }

        return BackupVersionInfo(
            recordName: record.recordID.recordName,
            date: info.date,
            size: info.size,
            version: info.version,
            isPinned: isPinned
        )
    }
}
