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
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        try await backupManager.restoreLatest()
        
        #expect(mockCloudStore.downloadCalled == true)
        #expect(mockDataRepository.clearCalled == true)
        #expect(mockDataRepository.importCalled == true)
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
    
    func isAvailable() async -> Bool {
        isAvailableResult
    }
    
    func uploadBackup(_ data: Data) async throws {
        uploadCalled = true
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
    
    func exportAllData() throws -> Data {
        exportCalled = true
        return exportData
    }
    
    func importAllData(_ data: Data) throws {
        importCalled = true
    }
    
    func clearAllData() throws {
        clearCalled = true
    }
}
