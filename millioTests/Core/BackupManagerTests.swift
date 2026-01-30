//
//  BackupManagerTests.swift
//  millioTests
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import Testing
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
        #expect(mockDataRepository.exportCalled == true)
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

    @Test("Restore latest treats corrupted envelope as backupCorrupted (no legacy fallback)")
    func testRestoreLatestCorruptedEnvelope() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        
        var data = Data()
        var headerLength = UInt32(2).bigEndian
        withUnsafeBytes(of: &headerLength) { data.append(contentsOf: $0) }
        data.append(Data("{x".utf8))
        data.append(Data("payload".utf8))
        mockCloudStore.downloadData = data
        
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        do {
            try await backupManager.restoreLatest()
            #expect(Bool(false))
        } catch let error as AppError {
            #expect(error == .backupCorrupted)
        } catch {
            #expect(Bool(false))
        }
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
    var backupInfo: BackupInfo?
    var uploadedData: Data?
    
    func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    func uploadBackup(_ data: Data) async throws {
        uploadCalled = true
        uploadedData = data
    }
    
    func downloadLatestBackup() async throws -> Data? {
        downloadCalled = true
        return downloadData
    }
    
    func getLatestBackupInfo() async throws -> BackupInfo? {
        backupInfo
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
    var exportCalls = 0
    var importCalls = 0
    var clearCalls = 0
    
    func exportAllData() throws -> Data {
        exportCalls += 1
        return storage
    }
    
    func importAllData(_ data: Data) throws {
        importCalls += 1
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
