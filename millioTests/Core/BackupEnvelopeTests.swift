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
    
    @Test("BackupEnvelope looksLikeEnvelope detects packed data")
    func testLooksLikeEnvelopePackedData() throws {
        let metadata = BackupMetadata(version: .current, timestamp: Date(), schemaVersion: "2.0", modelCount: 0)
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        let packed = try BackupEnvelope.pack(header: header, payload: Data("payload".utf8))
        #expect(BackupEnvelope.looksLikeEnvelope(packed) == true)
        #expect(BackupEnvelope.looksLikeEnvelope(Data("not-envelope".utf8)) == false)
    }
    
    @Test("BackupEnvelope unpack fails for corrupted data")
    func testUnpackCorruptedFails() {
        #expect(throws: AppError.backupCorrupted) {
            _ = try BackupEnvelope.unpack(Data())
        }
        
        #expect(throws: AppError.backupCorrupted) {
            _ = try BackupEnvelope.unpack(Data([0, 0, 0, 0]))
        }
        
        #expect(throws: AppError.backupCorrupted) {
            _ = try BackupEnvelope.unpack(Data([0, 0, 0, 10, UInt8(ascii: "{")]))
        }
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
