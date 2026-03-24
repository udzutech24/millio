//
//  BackupManagerTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Testing
import CloudKit
@testable import millio

struct BackupManagerTests {
    @Test("Backup manager is available when iCloud is available")
    func testIsAvailable() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        let result = await backupManager.isAvailable()
        #expect(result == true)
    }
    
    @Test("Backup now succeeds when iCloud is available")
    func testBackupNowSuccess() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("test data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        try await backupManager.backupNow()
        
        #expect(mockCloudStore.uploadCalled == true)
        #expect(mockCloudStore.uploadedIsPinned == false)
        #expect(mockDataRepository.exportCalled == true)
    }

    @Test("saveVersionNow stores pinned backup version")
    func testSaveVersionNowStoresPinnedVersion() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("test data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        try await backupManager.saveVersionNow(passphrase: nil)

        #expect(mockCloudStore.uploadCalled == true)
        #expect(mockCloudStore.uploadedIsPinned == true)
    }

    @Test("Export selected version returns raw backup data with portable filename")
    func testExportVersionReturnsPortablePayload() async throws {
        let backupDate = Date(timeIntervalSince1970: 1_762_000_000)
        let payload = Data("export-me".utf8)
        let version = BackupVersionInfo(
            recordName: "snapshot-export",
            date: backupDate,
            size: Int64(payload.count),
            version: "2.0.0",
            isPinned: true
        )
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.downloadDataByRecordName["snapshot-export"] = payload
        mockCloudStore.listedVersions = [version]

        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: MockDataRepository()
        )

        let exported = try await backupManager.exportVersion(recordName: "snapshot-export")

        #expect(exported.data == payload)
        #expect(exported.versionInfo == version)
        #expect(exported.fileName.contains("millio-backup-"))
        #expect(exported.fileName.hasSuffix(".milliobackup"))
    }

    @Test("Import version keeps original metadata and stores backup as pinned")
    func testImportVersionKeepsOriginalMetadata() async throws {
        let originalDate = Date(timeIntervalSince1970: 1_700_000_000)
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: originalDate, schemaVersion: "2.0", modelCount: 0),
            compression: nil,
            encryption: nil
        )
        let rawData = try BackupEnvelope.pack(header: header, payload: Data("portable".utf8))

        let expectedImported = BackupVersionInfo(
            recordName: "snapshot-imported",
            date: originalDate,
            size: Int64(rawData.count),
            version: BackupVersion.current.stringValue,
            isPinned: true
        )

        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.importResult = expectedImported

        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: MockDataRepository()
        )

        let imported = try await backupManager.importVersion(from: rawData)

        #expect(imported == expectedImported)
        #expect(mockCloudStore.importedData == rawData)
        #expect(mockCloudStore.importedInfo?.date == originalDate)
        #expect(mockCloudStore.importedInfo?.version == BackupVersion.current.stringValue)
        #expect(mockCloudStore.importedIsPinned == true)
    }

    @Test("Import version rejects corrupted envelope")
    func testImportVersionRejectsCorruptedEnvelope() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true

        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: MockDataRepository()
        )

        var corrupted = Data()
        var headerLength = UInt32(2).bigEndian
        withUnsafeBytes(of: &headerLength) { corrupted.append(contentsOf: $0) }
        corrupted.append(Data("{x".utf8))
        corrupted.append(Data("payload".utf8))

        await #expect(throws: AppError.backupCorrupted) {
            try await backupManager.importVersion(from: corrupted)
        }
    }
    
    @Test("Backup now supports passphrase encryption (envelope header + decryptable payload)")
    func testBackupNowPassphraseEncryption() async throws {
        let passphrase = "test-passphrase"
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        
        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data((0..<4096).map { _ in UInt8.random(in: 0...255) })
        
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        try await backupManager.backupNow(passphrase: passphrase)
        
        guard let uploaded = mockCloudStore.uploadedData else {
            throw AppError.backupFailed("Test setup failed: uploaded data is nil")
        }
        
        let (header, payload) = try BackupEnvelope.unpack(uploaded)
        #expect(header.encryption?.algorithm == "aesgcm-passphrase")
        
        guard let kdf = header.encryption?.kdf else {
            throw AppError.backupFailed("Test setup failed: kdf is nil")
        }
        
        let decrypted = try PassphraseBackupEncryption.decrypt(payload, passphrase: passphrase, kdf: kdf)
        #expect(decrypted == mockDataRepository.exportData)
    }
    
    @Test("Backup now throws error when iCloud is unavailable")
    func testBackupNowICloudUnavailable() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = false
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        await #expect(throws: AppError.self) {
            try await backupManager.backupNow()
        }
    }
    
    @Test("Restore latest succeeds with valid backup")
    func testRestoreLatestSuccess() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.downloadData = Data("restored data".utf8)
        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        try await backupManager.restoreLatest()
        
        #expect(mockCloudStore.downloadCalled == true)
        #expect(mockDataRepository.clearCalled == true)
        #expect(mockDataRepository.importCalled == true)
        #expect(mockDataRepository.exportCalled == true)
    }

    @Test("Restore latest rolls back to previous data if import fails")
    func testRestoreLatestRollbackOnImportFailure() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.downloadData = Data("new data".utf8)
        
        let repo = FailingImportDataRepository()
        repo.storage = Data("previous data".utf8)
        repo.failNextImport = true
        
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: repo
        )
        
        await #expect(throws: AppError.self) {
            try await backupManager.restoreLatest()
        }
        
        #expect(repo.storage == Data("previous data".utf8))
        #expect(repo.exportCalls == 1)
        #expect(repo.clearCalls >= 1)
        #expect(repo.importCalls >= 2)
    }
    
    @Test("Restore latest supports passphrase-encrypted backups")
    func testRestoreLatestPassphraseEncryptedBackup() async throws {
        let passphrase = "test-passphrase"
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        
        let plaintext = Data((0..<2048).map { _ in UInt8.random(in: 0...255) })
        let encrypted = try PassphraseBackupEncryption.encrypt(plaintext, passphrase: passphrase)
        
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
            compression: nil,
            encryption: BackupEncryptionInfo(algorithm: "aesgcm-passphrase", kdf: encrypted.kdf)
        )
        mockCloudStore.downloadData = try BackupEnvelope.pack(header: header, payload: encrypted.encrypted)
        
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        try await backupManager.restoreLatest(passphrase: passphrase)
        
        #expect(mockDataRepository.clearCalled == true)
        #expect(mockDataRepository.importCalled == true)
        #expect(mockDataRepository.importedData == plaintext)
    }
    
    @Test("Restore latest fails without passphrase for passphrase-encrypted backups")
    func testRestoreLatestPassphraseRequired() async {
        let passphrase = "test-passphrase"
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        
        let plaintext = Data((0..<512).map { _ in UInt8.random(in: 0...255) })
        let encrypted = try? PassphraseBackupEncryption.encrypt(plaintext, passphrase: passphrase)
        
        if let encrypted {
            let header = BackupEnvelopeHeader(
                formatVersion: BackupEnvelopeHeader.currentFormatVersion,
                metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
                compression: nil,
                encryption: BackupEncryptionInfo(algorithm: "aesgcm-passphrase", kdf: encrypted.kdf)
            )
            mockCloudStore.downloadData = try? BackupEnvelope.pack(header: header, payload: encrypted.encrypted)
        }
        
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        await #expect(throws: AppError.self) {
            try await backupManager.restoreLatest(passphrase: nil)
        }
    }

    @Test("Restore latest falls back to older snapshot when newest snapshot is corrupted")
    func testRestoreLatestFallsBackToOlderSnapshotOnCorruptedLatest() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-new", "snapshot-old"]

        var corruptedData = Data()
        var headerLength = UInt32(2).bigEndian
        withUnsafeBytes(of: &headerLength) { corruptedData.append(contentsOf: $0) }
        corruptedData.append(Data("{x".utf8))
        corruptedData.append(Data("payload".utf8))

        let expectedData = Data("restored-from-older-snapshot".utf8)
        mockCloudStore.downloadDataByRecordName = [
            "snapshot-new": corruptedData,
            "snapshot-old": expectedData
        ]

        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        try await backupManager.restoreLatest()

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-new", "snapshot-old"])
        #expect(mockDataRepository.importCalled == true)
        #expect(mockDataRepository.importedData == expectedData)
    }

    @Test("Restore latest falls back to older snapshot when newest snapshot fails checksum validation")
    func testRestoreLatestFallsBackToOlderSnapshotOnChecksumMismatch() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-new", "snapshot-old"]

        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
            compression: nil,
            encryption: nil
        )
        var corruptedCandidate = try BackupEnvelope.pack(header: header, payload: Data("payload".utf8))
        corruptedCandidate[corruptedCandidate.index(before: corruptedCandidate.endIndex)] ^= 0xFF

        let expectedData = Data("restored-from-older-snapshot".utf8)
        mockCloudStore.downloadDataByRecordName = [
            "snapshot-new": corruptedCandidate,
            "snapshot-old": expectedData
        ]

        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        try await backupManager.restoreLatest()

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-new", "snapshot-old"])
        #expect(mockDataRepository.importCalled == true)
        #expect(mockDataRepository.importedData == expectedData)
    }

    @Test("Restore latest preflight skips unsupported compression and restores older snapshot")
    func testRestoreLatestPreflightSkipsUnsupportedCompression() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-new", "snapshot-old"]

        let unsupportedCompressionHeader = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
            compression: BackupCompressionInfo(algorithm: "gzip", originalSize: 128),
            encryption: nil
        )
        let unsupportedCompressedCandidate = try BackupEnvelope.pack(
            header: unsupportedCompressionHeader,
            payload: Data("compressed-payload".utf8)
        )

        let expectedData = Data("fallback-restored-data".utf8)
        mockCloudStore.downloadDataByRecordName = [
            "snapshot-new": unsupportedCompressedCandidate,
            "snapshot-old": expectedData
        ]

        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        try await backupManager.restoreLatest()

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-new", "snapshot-old"])
        #expect(mockDataRepository.importCalled == true)
        #expect(mockDataRepository.importedData == expectedData)
    }

    @Test("Restore selected version restores only requested record")
    func testRestoreSelectedVersionUsesOnlyRequestedRecord() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.downloadDataByRecordName = [
            "snapshot-target": Data("target-data".utf8),
            "snapshot-other": Data("other-data".utf8)
        ]

        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        try await backupManager.restoreVersion(recordName: "snapshot-target", passphrase: nil)

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-target"])
        #expect(mockDataRepository.importedData == Data("target-data".utf8))
    }

    @Test("Restore latest fails with restoreFailed when all snapshot candidates are corrupted or incompatible")
    func testRestoreLatestFailsWhenAllCandidatesAreInvalid() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-corrupted", "snapshot-incompatible"]

        var corruptedData = Data()
        var corruptedHeaderLength = UInt32(2).bigEndian
        withUnsafeBytes(of: &corruptedHeaderLength) { corruptedData.append(contentsOf: $0) }
        corruptedData.append(Data("{x".utf8))
        corruptedData.append(Data("payload".utf8))

        let incompatibleHeader = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion + 1,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
            compression: nil,
            encryption: nil
        )
        let incompatibleData = try? BackupEnvelope.pack(header: incompatibleHeader, payload: Data("payload".utf8))

        if let incompatibleData {
            mockCloudStore.downloadDataByRecordName = [
                "snapshot-corrupted": corruptedData,
                "snapshot-incompatible": incompatibleData
            ]
        }

        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        do {
            try await backupManager.restoreLatest()
            #expect(Bool(false))
        } catch let error as AppError {
            switch error {
            case .restoreFailed:
                #expect(true)
            default:
                #expect(Bool(false))
            }
        } catch {
            #expect(Bool(false))
        }

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-corrupted", "snapshot-incompatible"])
        #expect(mockDataRepository.importCalled == false)
    }

    @Test("Restore latest does not fallback to older snapshots when passphrase is required")
    func testRestoreLatestStopsOnPassphraseRequiredError() async throws {
        let passphrase = "test-passphrase"
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-passphrase", "snapshot-plain"]

        let plaintext = Data("secret backup payload".utf8)
        let encrypted = try PassphraseBackupEncryption.encrypt(plaintext, passphrase: passphrase)
        let passphraseHeader = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0),
            compression: nil,
            encryption: BackupEncryptionInfo(algorithm: "aesgcm-passphrase", kdf: encrypted.kdf)
        )
        let passphraseProtectedData = try BackupEnvelope.pack(header: passphraseHeader, payload: encrypted.encrypted)

        mockCloudStore.downloadDataByRecordName = [
            "snapshot-passphrase": passphraseProtectedData,
            "snapshot-plain": Data("plain-fallback".utf8)
        ]

        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        do {
            try await backupManager.restoreLatest(passphrase: nil)
            #expect(Bool(false))
        } catch let error as AppError {
            switch error {
            case .restoreFailed(let message):
                #expect(message == RestoreFailureCode.passphraseRequired.message)
            default:
                #expect(Bool(false))
            }
        }

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-passphrase"])
        #expect(mockDataRepository.importCalled == false)
    }

    @Test("Restore latest falls back to older snapshot when newest snapshot contains unknown model types")
    func testRestoreLatestFallsBackToOlderSnapshotOnUnknownModelTypes() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-new", "snapshot-old"]

        let incompatiblePayload: [String: Any] = [
            "metadata": [
                "version": ["major": BackupVersion.current.major, "minor": BackupVersion.current.minor, "patch": BackupVersion.current.patch],
                "timestamp": Date().timeIntervalSince1970,
                "schemaVersion": BackupMetadata.currentSchemaVersion,
                "modelCount": 1
            ],
            "models": [["_type": "UnknownType"]]
        ]
        let incompatibleData = try JSONSerialization.data(withJSONObject: incompatiblePayload)
        let expectedData = Data("fallback-restored-data".utf8)

        mockCloudStore.downloadDataByRecordName = [
            "snapshot-new": incompatibleData,
            "snapshot-old": expectedData
        ]

        let repository = FailingImportDataRepository()
        repository.storage = Data("existing data".utf8)
        repository.nextImportError = AppError.restoreFailed("\(DataRepository.unknownModelTypesErrorPrefix)UnknownType")
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: repository
        )

        try await backupManager.restoreLatest()

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-new", "snapshot-old"])
        #expect(repository.storage == expectedData)
    }

    @Test("Restore latest falls back to older snapshot when newest keychain snapshot cannot be decrypted on this device")
    func testRestoreLatestFallsBackWhenNewestKeychainSnapshotIsUnavailable() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        mockCloudStore.backupRecordNamesForRestore = ["snapshot-keychain", "snapshot-old"]

        let keychainHeader = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: BackupMetadata.currentSchemaVersion, modelCount: 0),
            compression: nil,
            encryption: BackupEncryptionInfo(algorithm: "aesgcm-keychain", kdf: nil)
        )
        let keychainProtectedData = try BackupEnvelope.pack(
            header: keychainHeader,
            payload: Data("encrypted-payload".utf8)
        )
        let expectedData = Data("fallback-restored-data".utf8)

        mockCloudStore.downloadDataByRecordName = [
            "snapshot-keychain": keychainProtectedData,
            "snapshot-old": expectedData
        ]

        let repository = FailingImportDataRepository()
        repository.storage = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: repository,
            encryption: ConditionalFailingBackupEncryption(failingPayload: Data("encrypted-payload".utf8))
        )

        try await backupManager.restoreLatest()

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-keychain", "snapshot-old"])
        #expect(repository.storage == expectedData)
    }

    @Test("Restore selected version stops when keychain snapshot cannot be decrypted on this device")
    func testRestoreSelectedVersionFailsWhenKeychainSnapshotIsUnavailable() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true

        let keychainHeader = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: BackupMetadata(version: .current, timestamp: Date(), schemaVersion: BackupMetadata.currentSchemaVersion, modelCount: 0),
            compression: nil,
            encryption: BackupEncryptionInfo(algorithm: "aesgcm-keychain", kdf: nil)
        )
        let keychainProtectedData = try BackupEnvelope.pack(
            header: keychainHeader,
            payload: Data("encrypted-payload".utf8)
        )
        mockCloudStore.downloadDataByRecordName = [
            "snapshot-keychain": keychainProtectedData
        ]

        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("existing data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository,
            encryption: ConditionalFailingBackupEncryption(failingPayload: Data("encrypted-payload".utf8))
        )

        do {
            try await backupManager.restoreVersion(recordName: "snapshot-keychain", passphrase: nil)
            #expect(Bool(false))
        } catch let error as AppError {
            #expect(error == RestoreFailureCode.keychainUnavailable.appError)
        }

        #expect(mockCloudStore.requestedRecordNames == ["snapshot-keychain"])
        #expect(mockDataRepository.importCalled == false)
    }
    
    @Test("Last backup info returns correct information")
    func testLastBackupInfo() async {
        let expectedInfo = BackupInfo(
            date: Date(),
            size: 1024,
            version: "1.0"
        )
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.backupInfo = expectedInfo
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        let info = await backupManager.lastBackupInfo()
        
        // Используем локальные переменные для избежания warnings в autoclosure
        let expectedDate = expectedInfo.date
        let expectedSize = expectedInfo.size
        let infoDate = info?.date
        let infoSize = info?.size
        #expect(infoDate == expectedDate)
        #expect(infoSize == expectedSize)
    }
}

// MARK: - Mocks

final class MockCloudBackupStore: CloudBackupStoreProtocol {
    var isAvailableResult = false
    var uploadCalled = false
    var downloadCalled = false
    var downloadData: Data?
    var backupRecordNamesForRestore: [String] = ["latest_backup"]
    var requestedRecordNames: [String] = []
    var downloadDataByRecordName: [String: Data] = [:]
    var downloadErrorsByRecordName: [String: Error] = [:]
    var backupInfo: BackupInfo?
    var uploadedData: Data?
    var uploadedIsPinned: Bool?
    var importedData: Data?
    var importedInfo: BackupInfo?
    var importedIsPinned: Bool?
    var importResult: BackupVersionInfo?
    var listedVersions: [BackupVersionInfo] = []
    var deletedRecordNames: [String] = []
    
    func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    func uploadBackup(_ data: Data, isPinned: Bool) async throws {
        uploadCalled = true
        uploadedData = data
        uploadedIsPinned = isPinned
    }

    func importBackup(_ data: Data, info: BackupInfo?, isPinned: Bool) async throws -> BackupVersionInfo {
        importedData = data
        importedInfo = info
        importedIsPinned = isPinned
        return importResult ?? BackupVersionInfo(
            recordName: "snapshot-imported",
            date: info?.date ?? Date(),
            size: Int64(data.count),
            version: info?.version ?? "1.0",
            isPinned: isPinned
        )
    }
    
    func downloadLatestBackup() async throws -> Data? {
        downloadCalled = true
        return downloadData
    }

    func listBackupRecordNamesForRestore() async throws -> [String] {
        backupRecordNamesForRestore
    }

    func downloadBackup(recordName: String) async throws -> Data? {
        downloadCalled = true
        requestedRecordNames.append(recordName)
        if let error = downloadErrorsByRecordName[recordName] {
            throw error
        }
        if let data = downloadDataByRecordName[recordName] {
            return data
        }
        if recordName == "latest_backup" {
            return downloadData
        }
        return nil
    }
    
    func getLatestBackupInfo() async throws -> BackupInfo? {
        backupInfo
    }

    func listBackupVersions() async throws -> [BackupVersionInfo] {
        listedVersions
    }

    func deleteBackup(recordName: String) async throws {
        deletedRecordNames.append(recordName)
    }
}

private struct ConditionalFailingBackupEncryption: BackupEncryptionProtocol {
    let failingPayload: Data

    func encrypt(_ data: Data) throws -> Data {
        data
    }

    func decrypt(_ data: Data) throws -> Data {
        if data == failingPayload {
            throw AppError.securityFailed("Simulated keychain failure")
        }
        return data
    }
}

final class MockDataRepository: DataRepositoryProtocol {
    var exportCalled = false
    var importCalled = false
    var clearCalled = false
    var exportData = Data()
    var importedData: Data?
    
    func exportAllData() throws -> Data {
        exportCalled = true
        return exportData
    }
    
    func importAllData(_ data: Data) throws {
        importCalled = true
        importedData = data
    }
    
    func clearAllData() throws {
        clearCalled = true
    }
    
    func exportAllDataAsync() async throws -> Data {
        try exportAllData()
    }
    
    func importAllDataAsync(_ data: Data) async throws {
        try importAllData(data)
    }
    
    func clearAllDataAsync() async throws {
        try clearAllData()
    }
}

final class FailingImportDataRepository: DataRepositoryProtocol {
    var storage = Data()
    var failNextImport = false
    var nextImportError: AppError?
    var exportCalls = 0
    var importCalls = 0
    var clearCalls = 0
    
    func exportAllData() throws -> Data {
        exportCalls += 1
        return storage
    }
    
    func importAllData(_ data: Data) throws {
        importCalls += 1
        if let nextImportError {
            self.nextImportError = nil
            throw nextImportError
        }
        if failNextImport {
            failNextImport = false
            throw AppError.restoreFailed("Simulated import failure")
        }
        storage = data
    }
    
    func clearAllData() throws {
        clearCalls += 1
        storage = Data()
    }
    
    func exportAllDataAsync() async throws -> Data {
        try exportAllData()
    }
    
    func importAllDataAsync(_ data: Data) async throws {
        try importAllData(data)
    }
    
    func clearAllDataAsync() async throws {
        try clearAllData()
    }
}

@Suite(.serialized)
struct CloudBackupStoreTests {
    @Test("isAvailable возвращает true при CKAccountStatus.available")
    func testIsAvailableReturnsTrueWhenAccountAvailable() async {
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available))
        let result = await store.isAvailable()
        #expect(result == true)
    }
    
    @Test("isAvailable возвращает false при ошибке получения статуса аккаунта")
    func testIsAvailableReturnsFalseOnError() async {
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusError: CKError(.networkUnavailable)))
        let result = await store.isAvailable()
        #expect(result == false)
    }
    
    @Test("uploadBackup создает запись при CKError.unknownItem и сохраняет метаданные")
    func testUploadBackupCreatesRecordAndSavesMetadata() async throws {
        let db = FakeCloudBackupDatabase()
        db.recordToReturn = nil
        db.errorOnFetch = CKError(.unknownItem)
        
        let container = FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        let store = CloudBackupStore(container: container)
        
        let data = Data((0..<256).map { _ in UInt8.random(in: 0...255) })
        try await store.uploadBackup(data, isPinned: false)
        
        let saved = db.savedRecords.first {
            $0.recordType == "AppBackup" && $0.recordID.recordName == "latest_backup"
        }
        #expect(saved != nil)
        #expect(saved?["backupSize"] as? Int64 == Int64(data.count))
        #expect(saved?["backupDate"] as? Date != nil)
        #expect(saved?["backupVersion"] as? String != nil)
        #expect(saved?["backupData"] as? CKAsset != nil)
    }
    
    @Test("downloadLatestBackup возвращает nil при отсутствии записи (CKError.unknownItem)")
    func testDownloadReturnsNilWhenNoRecord() async throws {
        let db = FakeCloudBackupDatabase()
        db.errorOnFetch = CKError(.unknownItem)
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        let data = try await store.downloadLatestBackup()
        #expect(data == nil)
    }
    
    @Test("downloadLatestBackup возвращает nil при отсутствии backupData в записи")
    func testDownloadReturnsNilWhenNoAsset() async throws {
        let db = FakeCloudBackupDatabase()
        db.recordToReturn = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        let data = try await store.downloadLatestBackup()
        #expect(data == nil)
    }
    
    @Test("downloadLatestBackup возвращает данные при наличии CKAsset.fileURL")
    func testDownloadReturnsDataWhenAssetHasFileURL() async throws {
        let expected = Data("payload".utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        try expected.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        
        let record = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        record["backupData"] = CKAsset(fileURL: url)
        
        let db = FakeCloudBackupDatabase()
        db.recordToReturn = record
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        let downloaded = try await store.downloadLatestBackup()
        #expect(downloaded == expected)
    }
    
    @Test("downloadLatestBackup бросает ошибку, если файл CKAsset недоступен")
    func testDownloadThrowsWhenAssetFileIsUnavailable() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        try Data("payload".utf8).write(to: url)
        try FileManager.default.removeItem(at: url)
        
        let record = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        record["backupData"] = CKAsset(fileURL: url)
        
        let db = FakeCloudBackupDatabase()
        db.recordToReturn = record
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        await #expect(throws: AppError.self) {
            _ = try await store.downloadLatestBackup()
        }
    }
    
    @Test("getLatestBackupInfo возвращает nil при отсутствии записи (CKError.unknownItem)")
    func testGetLatestBackupInfoReturnsNilWhenNoRecord() async throws {
        let db = FakeCloudBackupDatabase()
        db.errorOnFetch = CKError(.unknownItem)
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        let info = try await store.getLatestBackupInfo()
        #expect(info == nil)
    }
    
    @Test("getLatestBackupInfo возвращает данные при наличии полей даты/размера/версии")
    func testGetLatestBackupInfoReturnsInfoWhenFieldsPresent() async throws {
        let record = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        let date = Date(timeIntervalSince1970: 123)
        record["backupDate"] = date
        record["backupSize"] = Int64(999)
        record["backupVersion"] = "2.0.0"
        
        let db = FakeCloudBackupDatabase()
        db.recordToReturn = record
        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        
        let info = try await store.getLatestBackupInfo()
        #expect(info?.date == date)
        #expect(info?.size == Int64(999))
        #expect(info?.version == "2.0.0")
    }

    @Test("uploadBackup хранит историю auto-snapshot и удаляет устаревшие записи по retention")
    func testUploadBackupKeepsSnapshotHistoryWithRetention() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db),
            maxSnapshots: 3
        )

        for index in 1...4 {
            try await store.uploadBackup(Data("payload-\(index)".utf8), isPinned: false)
        }

        let versions = try await store.listBackupVersions()
        #expect(versions.count == 3)
        #expect(versions.allSatisfy { $0.recordName != "latest_backup" })
        #expect(db.deletedRecordNames.count == 1)

        let latest = try await store.downloadLatestBackup()
        #expect(latest == Data("payload-4".utf8))
    }

    @Test("uploadBackup keeps only one auto backup version by default")
    func testUploadBackupKeepsSingleAutoBackupVersionByDefault() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        for index in 1...4 {
            try await store.uploadBackup(Data("payload-\(index)".utf8), isPinned: false)
        }

        let versions = try await store.listBackupVersions()
        #expect(versions.count == 1)
        #expect(versions.allSatisfy { $0.recordName != "latest_backup" })
        #expect(db.deletedRecordNames.count == 3)
    }

    @Test("importBackup stores pinned snapshot with provided original metadata")
    func testImportBackupStoresPinnedSnapshotWithProvidedMetadata() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )
        let payload = Data("imported-payload".utf8)
        let originalDate = Date(timeIntervalSince1970: 1_700_000_100)

        let imported = try await store.importBackup(
            payload,
            info: BackupInfo(date: originalDate, size: Int64(payload.count), version: "2.0.0"),
            isPinned: true
        )

        #expect(imported.date == originalDate)
        #expect(imported.version == "2.0.0")
        #expect(imported.isPinned == true)

        let saved = db.savedRecords.first {
            $0.recordType == "AppBackup" && $0.recordID.recordName == imported.recordName
        }
        #expect(saved?["backupDate"] as? Date == originalDate)
        #expect(saved?["backupVersion"] as? String == "2.0.0")
        #expect(saved?["isPinned"] as? Int == 1)
    }

    @Test("uploadBackup keeps pinned versions alongside retained auto snapshots")
    func testUploadBackupKeepsPinnedVersionsAlongsideRetainedAutoSnapshots() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db),
            maxSnapshots: 2
        )

        try await store.uploadBackup(Data("pinned".utf8), isPinned: true)
        try await store.uploadBackup(Data("auto-1".utf8), isPinned: false)
        try await store.uploadBackup(Data("auto-2".utf8), isPinned: false)
        try await store.uploadBackup(Data("auto-3".utf8), isPinned: false)

        let versions = try await store.listBackupVersions()
        #expect(versions.count == 3)
        #expect(versions.filter(\.isPinned).count == 1)
        #expect(versions.filter { !$0.isPinned }.count == 2)
        #expect(versions.contains(where: { $0.recordName == "latest_backup" }) == false)
        #expect(db.deletedRecordNames.count == 1)
    }

    @Test("uploadBackup limits pinned versions to four most recent snapshots by default")
    func testUploadBackupLimitsPinnedVersionsToFourMostRecentSnapshotsByDefault() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        for index in 1...5 {
            try await store.uploadBackup(Data("pinned-\(index)".utf8), isPinned: true)
        }

        let versions = try await store.listBackupVersions()
        let pinnedVersions = versions.filter(\.isPinned)

        #expect(pinnedVersions.count == 4)
        #expect(versions.filter { !$0.isPinned }.isEmpty)
        #expect(db.deletedRecordNames.count == 1)
    }

    @Test("uploadBackup applies pinned and auto retention independently")
    func testUploadBackupAppliesPinnedAndAutoRetentionIndependently() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db),
            maxSnapshots: 2,
            maxPinnedSnapshots: 5
        )

        for index in 1...6 {
            try await store.uploadBackup(Data("pinned-\(index)".utf8), isPinned: true)
        }

        for index in 1...3 {
            try await store.uploadBackup(Data("auto-\(index)".utf8), isPinned: false)
        }

        let versions = try await store.listBackupVersions()
        #expect(versions.filter(\.isPinned).count == 5)
        #expect(versions.filter { !$0.isPinned }.count == 2)
        #expect(versions.count == 7)
        #expect(db.deletedRecordNames.count == 2)
    }

    @Test("listBackupVersions prunes existing excess backups down to four manual and one auto")
    func testListBackupVersionsPrunesExistingExcessBackups() async throws {
        let db = FakeCloudBackupDatabase()
        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        for index in 0..<6 {
            let record = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_pinned_\(index)"))
            record["backupDate"] = Date(timeIntervalSince1970: TimeInterval(1_000 + index))
            record["backupSize"] = Int64(100 + index)
            record["backupVersion"] = "2.0.0"
            record["isPinned"] = 1
            db.recordsByName[record.recordID.recordName] = record
        }

        for index in 0..<3 {
            let record = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_auto_\(index)"))
            record["backupDate"] = Date(timeIntervalSince1970: TimeInterval(2_000 + index))
            record["backupSize"] = Int64(200 + index)
            record["backupVersion"] = "2.0.0"
            record["isPinned"] = 0
            db.recordsByName[record.recordID.recordName] = record
        }

        let versions = try await store.listBackupVersions()

        #expect(versions.count == 5)
        #expect(versions.filter(\.isPinned).count == 4)
        #expect(versions.filter { !$0.isPinned }.count == 1)
        #expect(db.deletedRecordNames.count == 4)
    }

    @Test("downloadLatestBackup fallback к legacy latest, если index указывает на отсутствующие snapshots")
    func testDownloadLatestBackupFallsBackToLegacyWhenIndexIsStale() async throws {
        let db = FakeCloudBackupDatabase()

        let staleEntries: [[String: Any]] = [[
            "recordName": "snapshot_missing_1",
            "date": Date().timeIntervalSince1970,
            "size": Int64(10),
            "version": "2.0.0"
        ]]
        let staleEntriesData = try JSONSerialization.data(withJSONObject: staleEntries)
        let indexRecord = CKRecord(recordType: "AppBackupIndex", recordID: CKRecord.ID(recordName: "backup_index"))
        indexRecord["entriesJSON"] = String(decoding: staleEntriesData, as: UTF8.self)
        db.recordsByName["backup_index"] = indexRecord

        let payload = Data("legacy-fallback".utf8)
        let payloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        try payload.write(to: payloadURL)
        defer { try? FileManager.default.removeItem(at: payloadURL) }

        let legacyRecord = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        legacyRecord["backupData"] = CKAsset(fileURL: payloadURL)
        legacyRecord["backupDate"] = Date()
        legacyRecord["backupSize"] = Int64(payload.count)
        legacyRecord["backupVersion"] = "2.0.0"
        db.recordsByName["latest_backup"] = legacyRecord

        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))
        let downloaded = try await store.downloadLatestBackup()

        #expect(downloaded == payload)
    }

    @Test("listBackupVersions and downloadLatestBackup ignore corrupted backup_index when snapshot records exist")
    func testSnapshotRecordsRemainSourceOfTruthWhenIndexIsCorrupted() async throws {
        let db = FakeCloudBackupDatabase()

        let corruptedIndexRecord = CKRecord(recordType: "AppBackupIndex", recordID: CKRecord.ID(recordName: "backup_index"))
        corruptedIndexRecord["entriesJSON"] = "{not-valid-json"
        db.recordsByName["backup_index"] = corruptedIndexRecord

        let payload = Data("snapshot-payload".utf8)
        let payloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        try payload.write(to: payloadURL)
        defer { try? FileManager.default.removeItem(at: payloadURL) }

        let snapshotRecord = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_live"))
        snapshotRecord["backupData"] = CKAsset(fileURL: payloadURL)
        snapshotRecord["backupDate"] = Date(timeIntervalSince1970: 1234)
        snapshotRecord["backupSize"] = Int64(payload.count)
        snapshotRecord["backupVersion"] = "2.0.0"
        snapshotRecord["isPinned"] = 0
        db.recordsByName["snapshot_live"] = snapshotRecord

        let store = CloudBackupStore(container: FakeCloudBackupContainer(accountStatusResult: .available, database: db))

        let versions = try await store.listBackupVersions()
        let downloaded = try await store.downloadLatestBackup()

        #expect(versions.count == 1)
        #expect(versions.first?.recordName == "snapshot_live")
        #expect(downloaded == payload)
    }

    @Test("uploadBackup succeeds when backup_index cache update fails")
    func testUploadBackupSucceedsWhenIndexCacheWriteFails() async throws {
        let db = FakeCloudBackupDatabase()
        db.saveErrorByRecordName["backup_index"] = CKError(.serverRecordChanged)

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        let payload = Data("payload".utf8)
        try await store.uploadBackup(payload, isPinned: false)

        let versions = try await store.listBackupVersions()
        let downloaded = try await store.downloadLatestBackup()

        #expect(versions.count == 1)
        #expect(versions.first?.recordName.hasPrefix("snapshot_") == true)
        #expect(downloaded == payload)
    }

    @Test("uploadBackup succeeds when snapshot query is not supported but index path is available")
    func testUploadBackupSucceedsWhenSnapshotQueryIsNotSupported() async throws {
        let db = FakeCloudBackupDatabase()
        db.recordsError = NSError(
            domain: CKError.errorDomain,
            code: CKError.invalidArguments.rawValue,
            userInfo: [
                NSLocalizedFailureReasonErrorKey: "Field 'recordName' is not marked queryable"
            ]
        )

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        let payload = Data("payload".utf8)
        try await store.uploadBackup(payload, isPinned: false)

        let versions = try await store.listBackupVersions()
        let downloaded = try await store.downloadLatestBackup()

        #expect(versions.count == 1)
        #expect(versions.first?.recordName.hasPrefix("snapshot_") == true)
        #expect(downloaded == payload)
    }

    @Test("uploadBackup maps missing production schema to actionable AppError")
    func testUploadBackupMapsProductionSchemaError() async {
        let db = FakeCloudBackupDatabase()
        db.saveErrorByRecordName["__default__"] = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Unknown error",
                NSLocalizedFailureReasonErrorKey: "Error saving record <CKRecordID: 0x1; recordName=snapshot_1, zoneID=_defaultZone:__defaultOwner__> to server: Cannot create new type AppBackup in production schema"
            ]
        )

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        await #expect(throws: AppError.backupFailed("CloudKit backup operation failed: CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds.")) {
            try await store.uploadBackup(Data("payload".utf8), isPinned: false)
        }
    }

    @Test("uploadBackup maps direct missing record type message to actionable AppError")
    func testUploadBackupMapsDirectMissingRecordTypeMessage() async {
        let db = FakeCloudBackupDatabase()
        db.saveErrorByRecordName["__default__"] = NSError(
            domain: CKError.errorDomain,
            code: CKError.serverRejectedRequest.rawValue,
            userInfo: [
                NSLocalizedDescriptionKey: "Unknown error",
                NSLocalizedFailureReasonErrorKey: "CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds."
            ]
        )

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        await #expect(throws: AppError.backupFailed("CloudKit backup operation failed: CloudKit production schema is missing record type 'AppBackup'. Deploy the latest schema to production before using TestFlight or App Store builds.")) {
            try await store.uploadBackup(Data("payload".utf8), isPinned: false)
        }
    }

    @Test("deleteBackup removes snapshot even when backup_index cache resync fails")
    func testDeleteBackupSucceedsWhenIndexCacheResyncFails() async throws {
        let db = FakeCloudBackupDatabase()
        let payload = Data("payload".utf8)
        let payloadURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("backup")
        try payload.write(to: payloadURL)
        defer { try? FileManager.default.removeItem(at: payloadURL) }

        let snapshotRecord = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_delete_me"))
        snapshotRecord["backupData"] = CKAsset(fileURL: payloadURL)
        snapshotRecord["backupDate"] = Date(timeIntervalSince1970: 1234)
        snapshotRecord["backupSize"] = Int64(payload.count)
        snapshotRecord["backupVersion"] = "2.0.0"
        snapshotRecord["isPinned"] = 0
        db.recordsByName["snapshot_delete_me"] = snapshotRecord

        db.saveErrorByRecordName["backup_index"] = CKError(.serverRecordChanged)

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        try await store.deleteBackup(recordName: "snapshot_delete_me")

        let versions = try await store.listBackupVersions()
        let downloaded = try await store.downloadLatestBackup()

        #expect(versions.isEmpty)
        #expect(downloaded == nil)
        #expect(db.deletedRecordNames.contains("snapshot_delete_me"))
    }

    @Test("listBackupVersions ignores malformed snapshot records and keeps valid ones")
    func testListBackupVersionsIgnoresMalformedSnapshotRecords() async throws {
        let db = FakeCloudBackupDatabase()

        let malformed = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_bad"))
        malformed["backupDate"] = Date()
        db.recordsByName["snapshot_bad"] = malformed

        let valid = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_good"))
        valid["backupDate"] = Date(timeIntervalSince1970: 2000)
        valid["backupSize"] = Int64(42)
        valid["backupVersion"] = "2.0.0"
        valid["isPinned"] = 1
        db.recordsByName["snapshot_good"] = valid

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        let versions = try await store.listBackupVersions()

        #expect(versions.count == 1)
        #expect(versions.first?.recordName == "snapshot_good")
        #expect(versions.first?.isPinned == true)
    }

    @Test("getLatestBackupInfo falls back to legacy latest when snapshot records are malformed")
    func testGetLatestBackupInfoFallsBackToLegacyWhenSnapshotsMalformed() async throws {
        let db = FakeCloudBackupDatabase()

        let malformed = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "snapshot_bad"))
        malformed["backupDate"] = Date()
        db.recordsByName["snapshot_bad"] = malformed

        let legacy = CKRecord(recordType: "AppBackup", recordID: CKRecord.ID(recordName: "latest_backup"))
        let legacyDate = Date(timeIntervalSince1970: 3000)
        legacy["backupDate"] = legacyDate
        legacy["backupSize"] = Int64(99)
        legacy["backupVersion"] = "2.0.0"
        db.recordsByName["latest_backup"] = legacy

        let store = CloudBackupStore(
            container: FakeCloudBackupContainer(accountStatusResult: .available, database: db)
        )

        let info = try await store.getLatestBackupInfo()

        #expect(info?.date == legacyDate)
        #expect(info?.size == Int64(99))
        #expect(info?.version == "2.0.0")
    }
}

final class FakeCloudBackupContainer: CloudBackupContainerProtocol {
    private let databaseImpl: CloudBackupDatabaseProtocol
    private let statusResult: CKAccountStatus?
    private let statusError: Error?
    
    init(
        accountStatusResult: CKAccountStatus? = nil,
        accountStatusError: Error? = nil,
        database: CloudBackupDatabaseProtocol = FakeCloudBackupDatabase()
    ) {
        self.databaseImpl = database
        self.statusResult = accountStatusResult
        self.statusError = accountStatusError
    }
    
    var privateCloudDatabase: CloudBackupDatabaseProtocol { databaseImpl }
    
    func accountStatus() async throws -> CKAccountStatus {
        if let statusError { throw statusError }
        return statusResult ?? .couldNotDetermine
    }
}

final class FakeCloudBackupDatabase: CloudBackupDatabaseProtocol {
    var errorOnFetch: Error?
    var recordsError: Error?
    var recordToReturn: CKRecord?
    var lastSavedRecord: CKRecord?
    var recordsByName: [String: CKRecord] = [:]
    var savedRecords: [CKRecord] = []
    var deletedRecordNames: [String] = []
    var saveErrorByRecordName: [String: Error] = [:]
    private var persistedAssetURLs: [URL] = []
    
    func record(for recordID: CKRecord.ID) async throws -> CKRecord {
        if let errorOnFetch { throw errorOnFetch }
        if let stored = recordsByName[recordID.recordName] { return stored }
        if let recordToReturn { return recordToReturn }
        return CKRecord(recordType: "AppBackup", recordID: recordID)
    }

    func records(recordType: String) async throws -> [CKRecord] {
        if let recordsError { throw recordsError }
        if let errorOnFetch { throw errorOnFetch }
        return recordsByName.values.filter { $0.recordType == recordType }
    }
    
    func save(_ record: CKRecord) async throws -> CKRecord {
        if let saveError = saveErrorByRecordName[record.recordID.recordName] {
            throw saveError
        }
        if let saveError = saveErrorByRecordName["__default__"] {
            throw saveError
        }
        let persisted = try materializeRecord(record)
        lastSavedRecord = persisted
        savedRecords.append(persisted)
        recordsByName[persisted.recordID.recordName] = persisted
        return persisted
    }

    func deleteRecord(withID recordID: CKRecord.ID) async throws {
        deletedRecordNames.append(recordID.recordName)
        recordsByName.removeValue(forKey: recordID.recordName)
    }

    deinit {
        for url in persistedAssetURLs {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func materializeRecord(_ record: CKRecord) throws -> CKRecord {
        let copy = CKRecord(recordType: record.recordType, recordID: record.recordID)

        for key in record.allKeys() {
            if let asset = record[key] as? CKAsset,
               let sourceURL = asset.fileURL {
                let persistedURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("backup")
                let data = try Data(contentsOf: sourceURL)
                try data.write(to: persistedURL, options: .atomic)
                persistedAssetURLs.append(persistedURL)
                copy[key] = CKAsset(fileURL: persistedURL)
                continue
            }

            if let value = record[key] {
                copy[key] = value
            }
        }

        return copy
    }
}
