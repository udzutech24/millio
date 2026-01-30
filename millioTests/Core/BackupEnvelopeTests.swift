import Foundation
import Testing
@testable import millio

struct BackupEnvelopeTests {
    @Test("BackupEnvelope pack/unpack roundtrip")
    func testPackUnpackRoundtrip() throws {
        let metadata = BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0)
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        let payload = Data("payload".utf8)
        
        let packed = try BackupEnvelope.pack(header: header, payload: payload)
        let (unpackedHeader, unpackedPayload) = try BackupEnvelope.unpack(packed)
        
        #expect(unpackedHeader.formatVersion == BackupEnvelopeHeader.currentFormatVersion)
        #expect(unpackedPayload == payload)
    }
    
    @Test("Restore fails for unsupported envelope version")
    func testRestoreFailsForUnsupportedEnvelopeVersion() async {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        
        let metadata = BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0)
        let header = BackupEnvelopeHeader(
            formatVersion: 999,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        let packed = try? BackupEnvelope.pack(header: header, payload: Data("payload".utf8))
        mockCloudStore.downloadData = packed
        
        let mockDataRepository = MockDataRepository()
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )
        
        await #expect(throws: AppError.self) {
            try await backupManager.restoreLatest()
        }
    }
}

