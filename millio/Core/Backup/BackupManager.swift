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
    func saveVersionNow(passphrase: String?) async throws
    func exportVersion(recordName: String) async throws -> BackupTransferPayload
    func importVersion(from data: Data) async throws -> BackupVersionInfo
    func restoreLatest() async throws
    func restoreLatest(passphrase: String?) async throws
    func restoreVersion(recordName: String, passphrase: String?) async throws
    func listBackupVersions() async -> [BackupVersionInfo]
    func deleteBackupVersion(recordName: String) async throws
    func lastBackupInfo() async -> BackupInfo?
}

actor BackupManager: BackupManagerProtocol {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "millio", category: "BackupManager")
    private let cloudStore: CloudBackupStoreProtocol
    private let dataRepository: DataRepositoryProtocol
    private let staticEncryption: BackupEncryptionProtocol?
    private let usesSettingsEncryption: Bool
    private var backupTask: Task<Void, Never>?

    /// Хук «стор заменён восстановлением»: вызывается один раз после УСПЕШНОГО импорта бэкапа в том же
    /// сеансе. Нужен для self-heal легаси→core миграции — restore до-AccountsCore-бэкапа возвращает
    /// легаси-скелет без ядра, и без немедленного прогона миграции счета невидимы до перезапуска
    /// (RestoreView лишь ставит lifecycle=.ready и dismiss). Транспорт (этот actor) не знает о ядре —
    /// реальный прогон живёт в app-слое (DIContainer). См. plans/2026-07-12__legacy-migration-self-heal.md.
    private let onDidReplaceStore: (@MainActor () async -> Void)?
    private let historicalValuationScopeID: String?
    private let historicalValuationReadiness: HistoricalValuationReadinessCoordinator

    private enum RestoreCandidateDecision {
        case ready(score: Int, reason: RestoreCandidateReason, detail: String?)
        case skip(reason: RestoreCandidateReason)
        case block(error: AppError, reason: RestoreCandidateReason)
    }

    private struct TaggedRestoreFailure: Error {
        let appError: AppError
        let reason: RestoreCandidateReason
    }

    private enum RestoreMode {
        case automatic
        case explicitVersion
    }
    
    init(
        cloudStore: CloudBackupStoreProtocol,
        dataRepository: DataRepositoryProtocol,
        encryption: BackupEncryptionProtocol? = nil,
        historicalValuationScopeID: String? = nil,
        historicalValuationReadiness: HistoricalValuationReadinessCoordinator = .shared,
        onDidReplaceStore: (@MainActor () async -> Void)? = nil
    ) {
        self.cloudStore = cloudStore
        self.dataRepository = dataRepository
        self.staticEncryption = encryption
        self.usesSettingsEncryption = false
        self.historicalValuationScopeID = historicalValuationScopeID
        self.historicalValuationReadiness = historicalValuationReadiness
        self.onDidReplaceStore = onDidReplaceStore
    }

    init(
        dataRepository: DataRepositoryProtocol,
        historicalValuationScopeID: String? = nil,
        historicalValuationReadiness: HistoricalValuationReadinessCoordinator = .shared,
        onDidReplaceStore: (@MainActor () async -> Void)? = nil
    ) {
        self.cloudStore = CloudBackupStore()
        self.dataRepository = dataRepository
        self.staticEncryption = nil
        self.usesSettingsEncryption = true
        self.historicalValuationScopeID = historicalValuationScopeID
        self.historicalValuationReadiness = historicalValuationReadiness
        self.onDidReplaceStore = onDidReplaceStore
    }
    
    func isAvailable() async -> Bool {
        await cloudStore.isAvailable()
    }
    
    func backupNow() async throws {
        try await backupNow(passphrase: nil)
    }
    
    func backupNow(passphrase: String?) async throws {
        try await performBackup(passphrase: passphrase, isPinned: false)
    }

    func saveVersionNow(passphrase: String?) async throws {
        try await performBackup(passphrase: passphrase, isPinned: true)
    }

    func exportVersion(recordName: String) async throws -> BackupTransferPayload {
        guard await isAvailable() else {
            throw AppError.iCloudUnavailable
        }
        guard let data = try await cloudStore.downloadBackup(recordName: recordName) else {
            throw restoreFailure(.backupNotFound)
        }

        let versionInfo = try await exportVersionInfo(recordName: recordName, data: data)
        return BackupTransferPayload(
            fileName: exportFileName(for: versionInfo),
            data: data,
            versionInfo: versionInfo
        )
    }

    func importVersion(from data: Data) async throws -> BackupVersionInfo {
        guard await isAvailable() else {
            throw AppError.iCloudUnavailable
        }
        guard !data.isEmpty else {
            throw AppError.backupCorrupted
        }

        let info = try inspectPortableBackupInfo(data)
        return try await cloudStore.importBackup(data, info: info, isPinned: true)
    }

    private func performBackup(passphrase: String?, isPinned: Bool) async throws {
        logger.info("Starting backup...")

        // Блокировка бэкапа во время reconciliation (Track B, митигация B1b №7): пока merge
        // guest→user не завершён, стор в промежуточном состоянии — бэкап мог бы зафиксировать
        // частичный набор. Флаг in-memory, снимается в defer сервиса merge.
        if ScopeMergeLock.shared.isMergeInProgress {
            logger.info("Backup отложен: идёт reconciliation данных")
            throw AppError.backupFailed("reconciliation in progress")
        }

        let dataRepository = self.dataRepository
        let encryption = resolvedEncryption()
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
                try await cloudStore.uploadBackup(packed, isPinned: isPinned)
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
        if let historicalValuationScopeID {
            historicalValuationReadiness.begin(
                scopeID: historicalValuationScopeID,
                operation: .restore
            )
        }
        
        await MainActor.run {
            EventBus.shared.publish(BackupEvent.restoreStarted)
        }
        
        let dataRepository = self.dataRepository
        let encryption = resolvedEncryption()
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

                let backupRecordNames = try await cloudStore.listBackupRecordNamesForRestore()
                try await self.restoreFromRecordNames(
                    backupRecordNames,
                    passphrase: passphrase,
                    mode: .automatic,
                    encryption: encryption,
                    dataRepository: dataRepository,
                    cloudStore: cloudStore
                )
            }
        
            logger.info("Restore completed successfully")
            if let historicalValuationScopeID {
                historicalValuationReadiness.complete(
                    scopeID: historicalValuationScopeID,
                    operation: .restore
                )
            }
            
            await MainActor.run {
                EventBus.shared.publish(BackupEvent.restoreCompleted)
            }
        } catch {
            if let historicalValuationScopeID {
                historicalValuationReadiness.fail(
                    scopeID: historicalValuationScopeID,
                    operation: .restore,
                    reasonCode: "restore_failed"
                )
            }
            let appError = (error as? AppError) ?? .unknown(error)
            await MainActor.run {
                EventBus.shared.publish(BackupEvent.restoreFailed(appError))
            }
            CrashReporting.log("Restore failed: \(String(describing: error))")
            CrashReporting.record(error: error)
            throw error
        }
    }

    func restoreVersion(recordName: String, passphrase: String?) async throws {
        logger.info("Starting restore from selected version...")
        if let historicalValuationScopeID {
            historicalValuationReadiness.begin(
                scopeID: historicalValuationScopeID,
                operation: .restore
            )
        }

        await MainActor.run {
            EventBus.shared.publish(BackupEvent.restoreStarted)
        }

        let dataRepository = self.dataRepository
        let encryption = resolvedEncryption()
        let cloudStore = self.cloudStore

        do {
            guard await self.isAvailable() else {
                throw AppError.iCloudUnavailable
            }
            try await self.restoreFromRecordNames(
                [recordName],
                passphrase: passphrase,
                mode: .explicitVersion,
                encryption: encryption,
                dataRepository: dataRepository,
                cloudStore: cloudStore
            )
            if let historicalValuationScopeID {
                historicalValuationReadiness.complete(
                    scopeID: historicalValuationScopeID,
                    operation: .restore
                )
            }
            await MainActor.run {
                EventBus.shared.publish(BackupEvent.restoreCompleted)
            }
        } catch {
            if let historicalValuationScopeID {
                historicalValuationReadiness.fail(
                    scopeID: historicalValuationScopeID,
                    operation: .restore,
                    reasonCode: "restore_failed"
                )
            }
            let appError = (error as? AppError) ?? .unknown(error)
            await MainActor.run {
                EventBus.shared.publish(BackupEvent.restoreFailed(appError))
            }
            CrashReporting.log("Restore selected version failed: \(String(describing: error))")
            CrashReporting.record(error: error)
            throw error
        }
    }

    func listBackupVersions() async -> [BackupVersionInfo] {
        do {
            return try await cloudStore.listBackupVersions()
        } catch {
            logger.error("Failed to list backup versions: \(error.localizedDescription)")
            return []
        }
    }

    func deleteBackupVersion(recordName: String) async throws {
        try await cloudStore.deleteBackup(recordName: recordName)
    }

    private func restoreFromRecordNames(
        _ backupRecordNames: [String],
        passphrase: String?,
        mode: RestoreMode,
        encryption: BackupEncryptionProtocol?,
        dataRepository: DataRepositoryProtocol,
        cloudStore: CloudBackupStoreProtocol
    ) async throws {
        guard !backupRecordNames.isEmpty else {
            throw self.restoreFailure(.backupNotFound)
        }

        var hasAnyCandidateData = false

        for (candidateIndex, recordName) in backupRecordNames.enumerated() {
            guard let downloadedData = try await cloudStore.downloadBackup(recordName: recordName) else {
                self.recordRestoreCandidateMetric(
                    stage: .download,
                    outcome: .skip,
                    reason: .missingRecordOrAsset,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 0
                )
                continue
            }
            hasAnyCandidateData = true

            switch self.preflightCandidate(downloadedData, passphrase: passphrase) {
            case .ready(let score, let reason, let detail):
                self.recordRestoreCandidateMetric(
                    stage: .preflight,
                    outcome: .ready,
                    reason: reason,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: score,
                    detail: detail
                )
            case .skip(let reason):
                self.recordRestoreCandidateMetric(
                    stage: .preflight,
                    outcome: .skip,
                    reason: reason,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 0
                )
                continue
            case .block(let error, let reason):
                self.recordRestoreCandidateMetric(
                    stage: .preflight,
                    outcome: .block,
                    reason: reason,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 0
                )
                throw error
            }

            do {
                try await self.restoreDownloadedBackup(
                    downloadedData,
                    passphrase: passphrase,
                    encryption: encryption,
                    dataRepository: dataRepository
                )
                self.recordRestoreCandidateMetric(
                    stage: .restore,
                    outcome: .success,
                    reason: .restored,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 100
                )
                return
            } catch let tagged as TaggedRestoreFailure {
                if self.shouldTryOlderSnapshot(after: tagged.appError, mode: mode) {
                    self.recordRestoreCandidateMetric(
                        stage: .restore,
                        outcome: .skip,
                        reason: .skipReason(for: tagged.appError),
                        recordName: recordName,
                        candidateIndex: candidateIndex,
                        score: 0
                    )
                    self.logger.warning("Skipping restore candidate '\(recordName, privacy: .public)' due to \(tagged.appError.localizedDescription, privacy: .public)")
                    continue
                }
                self.recordRestoreCandidateMetric(
                    stage: .restore,
                    outcome: .block,
                    reason: tagged.reason,
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 0
                )
                throw tagged.appError
            } catch let appError as AppError {
                if self.shouldTryOlderSnapshot(after: appError, mode: mode) {
                    self.recordRestoreCandidateMetric(
                        stage: .restore,
                        outcome: .skip,
                        reason: .skipReason(for: appError),
                        recordName: recordName,
                        candidateIndex: candidateIndex,
                        score: 0
                    )
                    self.logger.warning("Skipping restore candidate '\(recordName, privacy: .public)' due to \(appError.localizedDescription, privacy: .public)")
                    continue
                }
                self.recordRestoreCandidateMetric(
                    stage: .restore,
                    outcome: .block,
                    reason: .blockReason(for: appError),
                    recordName: recordName,
                    candidateIndex: candidateIndex,
                    score: 0
                )
                throw appError
            }
        }

        if hasAnyCandidateData {
            throw self.restoreFailure(.allCandidatesInvalid)
        }

        throw self.restoreFailure(.backupNotFound)
    }

    private func shouldTryOlderSnapshot(after error: AppError, mode: RestoreMode) -> Bool {
        switch error {
        case .backupCorrupted, .incompatibleSchemaVersion:
            return true
        case .restoreFailed(let message):
            if message == RestoreFailureCode.keychainUnavailable.message ||
                message == RestoreFailureCode.keychainKeyMissingOnDevice.message {
                return mode == .automatic
            }

            if message.hasPrefix(DataRepository.unknownModelTypesErrorPrefix) {
                return true
            }

            return false
        default:
            return false
        }
    }

    private func restoreFailure(_ code: RestoreFailureCode) -> AppError {
        code.appError
    }

    private func taggedRestoreFailure(_ code: RestoreFailureCode) -> TaggedRestoreFailure {
        TaggedRestoreFailure(
            appError: code.appError,
            reason: code.reason
        )
    }

    private func preflightCandidate(_ downloadedData: Data, passphrase: String?) -> RestoreCandidateDecision {
        guard BackupEnvelope.looksLikeEnvelope(downloadedData) else {
            // Legacy payload path: valid but с меньшей уверенностью в целостности схемы.
            return .ready(score: 50, reason: .legacyPayload, detail: nil)
        }

        let header: BackupEnvelopeHeader
        do {
            (header, _) = try BackupEnvelope.unpack(downloadedData)
        } catch {
            return .skip(reason: .corruptedEnvelope)
        }

        guard BackupEnvelopeHeader.isSupportedFormatVersion(header.formatVersion) else {
            return .skip(reason: .incompatibleEnvelopeVersion)
        }

        if let encryptionInfo = header.encryption {
            switch encryptionInfo.algorithm {
            case "aesgcm-passphrase":
                guard passphrase != nil else {
                    return .block(
                        error: restoreFailure(.passphraseRequired),
                        reason: RestoreFailureCode.passphraseRequired.reason
                    )
                }
                guard encryptionInfo.kdf != nil else {
                    return .skip(reason: .missingKDF)
                }
            case "aesgcm-keychain":
                break
            default:
                return .skip(reason: .unsupportedEncryption)
            }
        }

        if let compression = header.compression, compression.algorithm != "lzfse" {
            return .skip(reason: .unsupportedCompression)
        }

        var score = 100
        if header.encryption != nil {
            score -= 5
        }
        if header.compression != nil {
            score -= 5
        }
        return .ready(
            score: score,
            reason: .envelopeValid,
            detail: "format_v\(header.formatVersion)"
        )
    }

    private func recordRestoreCandidateMetric(
        stage: RestoreCandidateStage,
        outcome: RestoreCandidateOutcome,
        reason: RestoreCandidateReason,
        recordName: String,
        candidateIndex: Int,
        score: Int,
        detail: String? = nil
    ) {
        let safeRecordName = recordName.hasPrefix("snapshot_") ? "snapshot" : recordName
        let detailValue = detail ?? "-"
        CrashReporting.setCustomValue(stage.rawValue, forKey: "restore_candidate_stage")
        CrashReporting.setCustomValue(outcome.rawValue, forKey: "restore_candidate_outcome")
        CrashReporting.setCustomValue(reason.rawValue, forKey: "restore_candidate_reason")
        CrashReporting.setCustomValue(detailValue, forKey: "restore_candidate_detail")
        CrashReporting.setCustomValue(candidateIndex, forKey: "restore_candidate_index")
        CrashReporting.setCustomValue(score, forKey: "restore_candidate_score")
        CrashReporting.log(
            "restore_candidate stage=\(stage.rawValue) outcome=\(outcome.rawValue) reason=\(reason.rawValue) detail=\(detailValue) index=\(candidateIndex) score=\(score) record=\(safeRecordName)"
        )
    }

    private func restoreDownloadedBackup(
        _ downloadedData: Data,
        passphrase: String?,
        encryption: BackupEncryptionProtocol?,
        dataRepository: DataRepositoryProtocol
    ) async throws {
        let backupData = try decodeBackupPayload(
            downloadedData,
            passphrase: passphrase,
            encryption: encryption
        )
        try await replaceRepositoryDataWithBackup(backupData, dataRepository: dataRepository)
    }

    private func decodeBackupPayload(
        _ downloadedData: Data,
        passphrase: String?,
        encryption: BackupEncryptionProtocol?
    ) throws -> Data {
        var backupData: Data

        if BackupEnvelope.looksLikeEnvelope(downloadedData) {
            let (header, payload): (BackupEnvelopeHeader, Data)
            do {
                (header, payload) = try BackupEnvelope.unpack(downloadedData)
            } catch {
                throw AppError.backupCorrupted
            }
            guard BackupEnvelopeHeader.isSupportedFormatVersion(header.formatVersion) else {
                throw AppError.incompatibleSchemaVersion
            }

            backupData = payload

            if let encryptionInfo = header.encryption {
                switch encryptionInfo.algorithm {
                case "aesgcm-passphrase":
                    guard let passphrase else {
                        throw taggedRestoreFailure(.passphraseRequired)
                    }
                    guard let kdf = encryptionInfo.kdf else {
                        throw AppError.backupCorrupted
                    }
                    do {
                        backupData = try PassphraseBackupEncryption.decrypt(backupData, passphrase: passphrase, kdf: kdf)
                    } catch {
                        throw taggedRestoreFailure(.decryptFailed)
                    }
                case "aesgcm-keychain":
                    let decryptor = encryption ?? KeychainBackupEncryption()
                    do {
                        backupData = try decryptor.decrypt(backupData)
                    } catch {
                        throw taggedRestoreFailure(.keychainUnavailable)
                    }
                default:
                    throw AppError.backupCorrupted
                }
            }

            if let compression = header.compression {
                guard compression.algorithm == "lzfse" else {
                    throw AppError.backupCorrupted
                }
                backupData = try decompressLZFSE(backupData)
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
                    throw taggedRestoreFailure(.decryptFailed)
                }
            }

            backupData = decompressLZFSEIfNeeded(backupData)
        }

        return backupData
    }

    private func replaceRepositoryDataWithBackup(
        _ backupData: Data,
        dataRepository: DataRepositoryProtocol
    ) async throws {
        let previousData = try await dataRepository.exportAllDataAsync()
        let snapshotURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("millio-pre-restore-\(UUID().uuidString).json")
        do {
            try previousData.write(to: snapshotURL, options: .atomic)
        } catch {
            throw taggedRestoreFailure(.preRestoreSnapshotFailed)
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
                throw taggedRestoreFailure(.rollbackFailed)
            }

            throw error
        }

        // Достигается только на успешном импорте (rollback-ветка выше перебрасывает ошибку). Self-heal
        // легаси→core сразу, а не на следующий relaunch: restore мог вернуть стор без ядра.
        await onDidReplaceStore?()
    }
    
    func lastBackupInfo() async -> BackupInfo? {
        do {
            return try await cloudStore.getLatestBackupInfo()
        } catch {
            logger.warning("Backup info lookup degraded: \(error.localizedDescription)")
            return nil
        }
    }
    
    private func decompressLZFSE(_ data: Data) throws -> Data {
        try processCompressionStream(data, operation: COMPRESSION_STREAM_DECODE)
    }

    private func exportVersionInfo(recordName: String, data: Data) async throws -> BackupVersionInfo {
        let listedVersion = try await cloudStore.listBackupVersions()
            .first(where: { $0.recordName == recordName })
        if let listedVersion {
            return listedVersion
        }

        if let inspectedInfo = try inspectPortableBackupInfo(data) {
            return BackupVersionInfo(
                recordName: recordName,
                date: inspectedInfo.date,
                size: Int64(data.count),
                version: inspectedInfo.version,
                isPinned: true
            )
        }

        return BackupVersionInfo(
            recordName: recordName,
            date: Date(),
            size: Int64(data.count),
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            isPinned: true
        )
    }

    private func inspectPortableBackupInfo(_ data: Data) throws -> BackupInfo? {
        guard BackupEnvelope.looksLikeEnvelope(data) else {
            return nil
        }

        let header: BackupEnvelopeHeader
        do {
            (header, _) = try BackupEnvelope.unpack(data)
        } catch {
            throw AppError.backupCorrupted
        }

        guard BackupEnvelopeHeader.isSupportedFormatVersion(header.formatVersion) else {
            throw AppError.incompatibleSchemaVersion
        }

        if let encryptionInfo = header.encryption {
            switch encryptionInfo.algorithm {
            case "aesgcm-passphrase":
                guard encryptionInfo.kdf != nil else {
                    throw AppError.backupCorrupted
                }
            case "aesgcm-keychain":
                break
            default:
                throw AppError.backupCorrupted
            }
        }

        if let compression = header.compression, compression.algorithm != "lzfse" {
            throw AppError.backupCorrupted
        }

        return BackupInfo(
            date: header.metadata.timestamp,
            size: Int64(data.count),
            version: header.metadata.version.stringValue
        )
    }

    private func exportFileName(for versionInfo: BackupVersionInfo) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        let datePart = formatter.string(from: versionInfo.date)
        let sanitizedVersion = versionInfo.version.replacingOccurrences(of: "/", with: "-")
        return "millio-backup-\(datePart)-v\(sanitizedVersion).milliobackup"
    }

    private func resolvedEncryption() -> BackupEncryptionProtocol? {
        if let staticEncryption {
            return staticEncryption
        }
        guard usesSettingsEncryption, SettingsManager.shared.isEncryptionEnabled else {
            return nil
        }
        return KeychainBackupEncryption()
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
            throw BackupFailureCode.compressionInitializationFailed.appError
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
                        throw BackupFailureCode.compressionEncodeFailed.appError
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
