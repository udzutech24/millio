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
    func importBackup(_ data: Data, info: BackupInfo?, isPinned: Bool) async throws -> BackupVersionInfo
    func downloadLatestBackup() async throws -> Data?
    func listBackupRecordNamesForRestore() async throws -> [String]
    func downloadBackup(recordName: String) async throws -> Data?
    func getLatestBackupInfo() async throws -> BackupInfo?
    func listBackupVersions() async throws -> [BackupVersionInfo]
    func deleteBackup(recordName: String) async throws
}

private protocol BackupRecordNameProviding {
    var recordName: String { get }
}

extension BackupVersionInfo: BackupRecordNameProviding {}

final class CloudBackupStore: CloudBackupStoreProtocol {
    private static let defaultAutoSnapshotRetention = 3
    private static let defaultPinnedSnapshotRetention = 4
    #if DEBUG
    static let cloudKitEnvironment = "Development"
    #else
    static let cloudKitEnvironment = "Production"
    #endif
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
    private let maxSnapshots: Int?
    private let maxPinnedSnapshots: Int
    private let now: () -> Date

    private struct SnapshotCache {
        let versions: [BackupVersionInfo]
        let expiresAt: Date
    }
    private var snapshotCache: SnapshotCache?
    private let snapshotCacheTTL: TimeInterval = 30

    private struct BackupIndexEntry: Codable, BackupRecordNameProviding {
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
        maxSnapshots: Int? = defaultAutoSnapshotRetention,
        maxPinnedSnapshots: Int = defaultPinnedSnapshotRetention,
        now: @escaping () -> Date = Date.init
    ) {
        self.container = CKContainerAdapter(container: container)
        self.maxSnapshots = maxSnapshots.map { max(1, $0) }
        self.maxPinnedSnapshots = max(1, maxPinnedSnapshots)
        self.now = now
    }
    
    init(
        container: CloudBackupContainerProtocol,
        maxSnapshots: Int? = defaultAutoSnapshotRetention,
        maxPinnedSnapshots: Int = defaultPinnedSnapshotRetention,
        now: @escaping () -> Date = Date.init
    ) {
        self.container = container
        self.maxSnapshots = maxSnapshots.map { max(1, $0) }
        self.maxPinnedSnapshots = max(1, maxPinnedSnapshots)
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
        _ = try await storeBackup(
            data,
            isPinned: isPinned,
            backupDate: now(),
            backupVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        )
    }

    func importBackup(_ data: Data, info: BackupInfo?, isPinned: Bool) async throws -> BackupVersionInfo {
        try await storeBackup(
            data,
            isPinned: isPinned,
            backupDate: info?.date ?? now(),
            backupVersion: info?.version ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
        )
    }

    private func storeBackup(
        _ data: Data,
        isPinned: Bool,
        backupDate: Date,
        backupVersion: String
    ) async throws -> BackupVersionInfo {
        let result: BackupVersionInfo
        if isPinned {
            result = try await storePinnedBackup(
                data,
                backupDate: backupDate,
                backupVersion: backupVersion
            )
        } else {
            result = try await storeAutoBackup(
                data,
                backupDate: backupDate,
                backupVersion: backupVersion
            )
        }
        snapshotCache = nil
        // Layer 2: orphan cleanup — полный scan CloudKit после успешного snapshot.
        // Layer 1 (index-based в storePinnedBackup/storeAutoBackup) удаляет stale-записи по индексу.
        // Layer 2 — safety net для orphan-записей вне индекса (schema-миграции, другие устройства).
        // Ошибка prune не откатывает upload — best-effort.
        do {
            try await pruneExcessSnapshotsIfNeeded(using: container.privateCloudDatabase)
        } catch {
            logger.warning("Orphan prune after backup failed (non-fatal): \(self.descriptiveCloudKitError(error), privacy: .public)")
        }
        snapshotCache = nil  // prune мог населить кэш данными до удаления stale-записей
        return result
    }

    private func storePinnedBackup(
        _ data: Data,
        backupDate: Date,
        backupVersion: String
    ) async throws -> BackupVersionInfo {
        let privateDB = container.privateCloudDatabase

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
            snapshotRecord[snapshotPinnedField] = 1
            _ = try await privateDB.save(snapshotRecord)

            let newEntry = BackupIndexEntry(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: true
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

            logger.info("Backup uploaded successfully")
            return BackupVersionInfo(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: true
            )
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func storeAutoBackup(
        _ data: Data,
        backupDate: Date,
        backupVersion: String
    ) async throws -> BackupVersionInfo {
        let privateDB = container.privateCloudDatabase
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
            snapshotRecord[snapshotPinnedField] = 0
            _ = try await privateDB.save(snapshotRecord)

            let newEntry = BackupIndexEntry(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: false
            )
            let existingEntries = try await loadIndexEntries(from: privateDB)
            let indexUpdate = mergeIndexEntries(existingEntries, appending: newEntry)

            for stale in indexUpdate.staleEntries {
                do {
                    try await privateDB.deleteRecord(withID: CKRecord.ID(recordName: stale.recordName))
                } catch {
                    logger.warning("Failed to delete stale auto snapshot '\(stale.recordName, privacy: .public)': \(self.descriptiveCloudKitError(error), privacy: .public)")
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
                logger.warning("Failed to update legacy latest backup: \(self.descriptiveCloudKitError(error), privacy: .public)")
            }

            logger.info("Auto backup uploaded successfully")
            return BackupVersionInfo(
                recordName: snapshotRecordID.recordName,
                date: backupDate,
                size: Int64(data.count),
                version: backupVersion,
                isPinned: false
            )
        } catch {
            throw mapCloudKitError(error)
        }
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
        let versions = try await listBackupVersions()

        var orderedNames: [String] = []
        var seen = Set<String>()

        for version in versions {
            if seen.insert(version.recordName).inserted {
                orderedNames.append(version.recordName)
            }
        }

        if seen.isEmpty,
           seen.contains(legacyLatestRecordID.recordName) == false,
           try await hasLegacyBackupPayload(using: privateDB) {
            orderedNames.append(legacyLatestRecordID.recordName)
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
        let snapshotInfo = try await latestInfoFromSnapshots(using: privateDB)
        let autoInfo = try await legacyLatestInfo(using: privateDB)
        return [snapshotInfo, autoInfo]
            .compactMap { $0 }
            .max { lhs, rhs in lhs.date < rhs.date }
    }

    func listBackupVersions() async throws -> [BackupVersionInfo] {
        let privateDB = container.privateCloudDatabase
        var versions = try await listSnapshotVersions(using: privateDB)

        if let autoVersion = try await autoBackupVersion(using: privateDB),
           shouldAppendLegacyAutoVersion(autoVersion, to: versions) {
            versions.append(autoVersion)
        }

        let sorted = versions.sorted { $0.date > $1.date }
        for v in sorted {
            logger.info("BackupVersion recordName=\(v.recordName, privacy: .public) date=\(v.date, privacy: .public) size=\(v.size) version=\(v.version, privacy: .public) isPinned=\(v.isPinned) source=\(v.source.rawValue, privacy: .public) env=\(Self.cloudKitEnvironment, privacy: .public)")
        }
        return sorted
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
        snapshotCache = nil

        guard recordName != legacyLatestRecordID.recordName else {
            return
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
        legacyRecord[snapshotPinnedField] = 0
        do {
            _ = try await database.save(legacyRecord)
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func listSnapshotVersions(using database: CloudBackupDatabaseProtocol) async throws -> [BackupVersionInfo] {
        let currentTime = now()
        if let cache = snapshotCache, cache.expiresAt > currentTime {
            logger.info("BackupList source=cache count=\(cache.versions.count) env=\(Self.cloudKitEnvironment, privacy: .public)")
            return cache.versions
        }

        do {
            // AppBackup records — источник истины. backup_index — только best-effort cache / fallback.
            let records = try await database.records(recordType: snapshotRecordType)
            let versions = records
                .filter { $0.recordID != legacyLatestRecordID }
                .compactMap { r -> BackupVersionInfo? in
                    guard var v = snapshotVersionInfo(from: r) else { return nil }
                    v.source = .snapshotQuery
                    return v
                }
                .sorted { $0.date > $1.date }
            logger.info("BackupList source=snapshotQuery count=\(versions.count) env=\(Self.cloudKitEnvironment, privacy: .public)")
            if !versions.isEmpty {
                snapshotCache = SnapshotCache(versions: versions, expiresAt: now().addingTimeInterval(snapshotCacheTTL))
            }

            // Диагностика расхождения с индексом — только логируем, не перезаписываем в read-path.
            if let indexEntries = try? await loadIndexEntries(from: database), !indexEntries.isEmpty {
                let indexNames = Set(indexEntries.map(\.recordName))
                let queryNames = Set(versions.map(\.recordName))
                if indexNames != queryNames {
                    logger.warning("BackupList: index diverged from snapshotQuery — index:\(indexNames.count) query:\(queryNames.count), serving snapshotQuery")
                }
            }

            return versions
        } catch let error as CKError where error.code == .unknownItem {
            // Тип AppBackup ещё не создан в этом CloudKit environment — используем индекс как fallback.
            // Типичная причина: schema Development не задеплоена в Production через CloudKit Dashboard.
            logger.warning("BackupList: AppBackup record type не найден в CloudKit \(Self.cloudKitEnvironment, privacy: .public) (unknownItem) — schema не задеплоена в этот env? Falling back to index. \(error.localizedDescription, privacy: .public)")
        } catch where isSnapshotQueryUnsupported(error) {
            let reason = (error as NSError).userInfo[NSLocalizedFailureReasonErrorKey] as? String
                ?? error.localizedDescription
            logger.warning("BackupList: snapshotQuery unsupported в \(Self.cloudKitEnvironment, privacy: .public) — поле не помечено queryable в CloudKit Dashboard. Reason: \(reason, privacy: .public)")
        } catch {
            throw mapCloudKitError(error)
        }

        // Fallback: индекс (только когда snapshotQuery недоступен в этом environment).
        let indexEntries = try await loadIndexEntries(from: database)
        logger.info("BackupList source=index (fallback) count=\(indexEntries.count) env=\(Self.cloudKitEnvironment, privacy: .public)")
        return indexEntries
            .map {
                BackupVersionInfo(
                    recordName: $0.recordName,
                    date: $0.date,
                    size: $0.size,
                    version: $0.version,
                    isPinned: $0.isPinned,
                    source: .index
                )
            }
            .sorted { $0.date > $1.date }
    }

    private func mergeIndexEntries(
        _ existingEntries: [BackupIndexEntry],
        appending newEntry: BackupIndexEntry
    ) -> (retainedEntries: [BackupIndexEntry], staleEntries: [BackupIndexEntry]) {
        let dedupedEntries = [newEntry] + existingEntries.filter { $0.recordName != newEntry.recordName }
        let sortedEntries = dedupedEntries.sorted { $0.date > $1.date }
        let retainedNames = retainedRecordNames(
            pinnedEntries: sortedEntries.filter(\.isPinned),
            autoEntries: sortedEntries.filter { !$0.isPinned }
        )

        let retainedEntries = sortedEntries.filter { retainedNames.contains($0.recordName) }
        let staleEntries = sortedEntries.filter {
            !retainedNames.contains($0.recordName)
        }

        return (retainedEntries, staleEntries)
    }

    private func staleSnapshotEntries(from versions: [BackupVersionInfo]) -> [BackupVersionInfo] {
        let retainedRecordNames = retainedRecordNames(
            pinnedEntries: versions.filter(\.isPinned),
            autoEntries: versions.filter { !$0.isPinned }
        )

        return versions.filter {
            !retainedRecordNames.contains($0.recordName)
        }
    }

    private func pruneExcessSnapshotsIfNeeded(using database: CloudBackupDatabaseProtocol) async throws {
        let versions = try await listSnapshotVersions(using: database)

        // Удаляем только когда snapshotQuery вернул авторитетные данные из CloudKit.
        // Index fallback — read-cache: удалять записи по stale index опасно (ложные positives).
        guard versions.isEmpty || versions.allSatisfy({ $0.source == .snapshotQuery }) else {
            logger.info("Prune skipped: versions sourced from index fallback, snapshotQuery unavailable")
            return
        }

        let staleEntries = staleSnapshotEntries(from: versions)

        guard !staleEntries.isEmpty else { return }

        for staleEntry in staleEntries {
            do {
                try await database.deleteRecord(withID: CKRecord.ID(recordName: staleEntry.recordName))
            } catch {
                logger.warning("Failed to delete excess snapshot '\(staleEntry.recordName, privacy: .public)': \(self.descriptiveCloudKitError(error), privacy: .public)")
            }
        }

        let retainedEntries = versions.filter { version in
            staleEntries.contains(where: { $0.recordName == version.recordName }) == false
        }

        do {
            try await saveIndexEntries(
                retainedEntries.map {
                    BackupIndexEntry(
                        recordName: $0.recordName,
                        date: $0.date,
                        size: $0.size,
                        version: $0.version,
                        isPinned: $0.isPinned
                    )
                },
                to: database
            )
        } catch {
            logger.warning("Failed to save pruned backup index cache: \(self.descriptiveCloudKitError(error), privacy: .public)")
        }
    }

    private func retainedRecordNames<T>(
        pinnedEntries: [T],
        autoEntries: [T]
    ) -> Set<String> where T: BackupRecordNameProviding {
        let retainedPinned = pinnedEntries.prefix(maxPinnedSnapshots).map(\.recordName)
        let retainedAuto = if let maxSnapshots {
            Array(autoEntries.prefix(maxSnapshots).map(\.recordName))
        } else {
            autoEntries.map(\.recordName)
        }

        return Set(retainedPinned + retainedAuto)
    }

    private func shouldAppendLegacyAutoVersion(
        _ autoVersion: BackupVersionInfo,
        to versions: [BackupVersionInfo]
    ) -> Bool {
        guard versions.contains(where: { $0.recordName == autoVersion.recordName }) == false else {
            return false
        }

        return versions.contains {
            !$0.isPinned &&
            $0.date == autoVersion.date &&
            $0.size == autoVersion.size &&
            $0.version == autoVersion.version
        } == false
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

    private func hasLegacyBackupPayload(using database: CloudBackupDatabaseProtocol) async throws -> Bool {
        do {
            let record = try await database.record(for: legacyLatestRecordID)
            guard let asset = record["backupData"] as? CKAsset else {
                return false
            }
            return asset.fileURL != nil
        } catch let error as CKError where error.code == .unknownItem {
            return false
        } catch {
            throw mapCloudKitError(error)
        }
    }

    private func autoBackupVersion(using database: CloudBackupDatabaseProtocol) async throws -> BackupVersionInfo? {
        guard let info = try await legacyLatestInfo(using: database) else {
            return nil
        }

        logger.info("BackupList source=legacyLatest date=\(info.date, privacy: .public) size=\(info.size) env=\(Self.cloudKitEnvironment, privacy: .public)")
        return BackupVersionInfo(
            recordName: legacyLatestRecordID.recordName,
            date: info.date,
            size: info.size,
            version: info.version,
            isPinned: false,
            source: .legacyLatest
        )
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

    private func isSnapshotQueryUnsupported(_ error: Error) -> Bool {
        let nsError = error as NSError
        let reason = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let description = error.localizedDescription.lowercased()

        let isInvalidArguments = (error as? CKError)?.code == .invalidArguments
            || (nsError.domain == CKError.errorDomain && nsError.code == CKError.invalidArguments.rawValue)
        let mentionsQueryable = reason.contains("queryable")
            || reason.contains("not marked queryable")
            || description.contains("queryable")

        return isInvalidArguments && mentionsQueryable
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
