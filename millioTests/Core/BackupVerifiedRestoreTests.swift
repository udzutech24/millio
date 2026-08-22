import Foundation
import Testing
@testable import millio

struct BackupVerifiedRestoreTests {
    @Test("Verified restore accepts a legacy v2 envelope")
    func verifiedLegacyV2EnvelopeRestores() async throws {
        let previous = try Self.payload(modelCount: 1)
        let backupPayload = try Self.payload(modelCount: 4)
        let legacyEnvelope = try BackupEnvelope.pack(
            header: BackupEnvelopeHeader(
                formatVersion: BackupEnvelopeHeader.legacyFormatVersion,
                metadata: BackupMetadata(
                    version: BackupVersion(major: 2, minor: 0, patch: 0),
                    timestamp: Date(timeIntervalSince1970: 42),
                    schemaVersion: "2.0",
                    modelCount: 4
                ),
                compression: nil,
                encryption: nil
            ),
            payload: backupPayload
        )
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["legacy-v2"] = legacyEnvelope
        let repository = StatefulRecoveryRepository(storage: previous)
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        let receipt = try await manager.restoreVersionVerified(
            recordName: "legacy-v2",
            passphrase: nil,
            progress: nil
        )

        #expect(receipt.expectedModelCount == 4)
        #expect(receipt.importedModelCount == 4)
        #expect(receipt.isVerified)
    }

    @Test("Verified restore returns exact before/imported/after counts")
    func verifiedReceiptCounts() async throws {
        let previous = try Self.payload(modelCount: 1)
        let backupPayload = try Self.payload(modelCount: 3)
        let envelope = try BackupEnvelope.pack(
            header: BackupEnvelopeHeader(
                formatVersion: BackupEnvelopeHeader.currentFormatVersion,
                metadata: BackupMetadata(
                    timestamp: Date(timeIntervalSince1970: 42),
                    modelCount: 3
                ),
                compression: nil,
                encryption: nil
            ),
            payload: backupPayload
        )
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["verified"] = envelope
        let repository = StatefulRecoveryRepository(storage: previous)
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        let receipt = try await manager.restoreVersionVerified(
            recordName: "verified",
            passphrase: nil,
            progress: nil
        )

        #expect(receipt.expectedModelCount == 3)
        #expect(receipt.localModelCountBefore == 1)
        #expect(receipt.importedModelCount == 3)
        #expect(receipt.localModelCountAfter == 3)
        #expect(receipt.isVerified)
    }

    @Test("Verification mismatch rolls back the previous snapshot")
    func mismatchRollsBack() async throws {
        let previous = try Self.payload(modelCount: 2)
        let backupPayload = try Self.payload(modelCount: 3)
        let envelope = try BackupEnvelope.pack(
            header: BackupEnvelopeHeader(
                formatVersion: BackupEnvelopeHeader.currentFormatVersion,
                metadata: BackupMetadata(modelCount: 3),
                compression: nil,
                encryption: nil
            ),
            payload: backupPayload
        )
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["mismatch"] = envelope
        let repository = StatefulRecoveryRepository(
            storage: previous,
            corruptFirstImportedSnapshot: true
        )
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        await #expect(throws: RecoveryFailure.verificationMismatch(expected: 3, actual: 2)) {
            _ = try await manager.restoreVersionVerified(
                recordName: "mismatch",
                passphrase: nil,
                progress: nil
            )
        }

        #expect(await repository.currentStorage() == previous)
    }

    private static func payload(modelCount: Int) throws -> Data {
        let metadata = BackupMetadata(modelCount: modelCount)
        let models = (0..<modelCount).map { ["_type": "Fixture", "id": "\($0)"] }
        return try JSONSerialization.data(withJSONObject: [
            "metadata": try DataRepository.metadataToDict(metadata),
            "models": models
        ])
    }
}

private actor StatefulRecoveryRepository: DataRepositoryProtocol {
    private var storage: Data
    private var corruptFirstImportedSnapshot: Bool
    private var didCorrupt = false

    init(storage: Data, corruptFirstImportedSnapshot: Bool = false) {
        self.storage = storage
        self.corruptFirstImportedSnapshot = corruptFirstImportedSnapshot
    }

    nonisolated func exportAllData() throws -> Data { fatalError("async-only fixture") }
    nonisolated func importAllData(_ data: Data) throws { fatalError("async-only fixture") }
    nonisolated func clearAllData() throws { fatalError("async-only fixture") }

    func exportAllDataAsync() async throws -> Data { storage }

    func importAllDataAsync(_ data: Data) async throws {
        if corruptFirstImportedSnapshot, !didCorrupt {
            didCorrupt = true
            let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            var models = object["models"] as! [[String: Any]]
            if !models.isEmpty { models.removeLast() }
            var changed = object
            changed["models"] = models
            storage = try JSONSerialization.data(withJSONObject: changed)
        } else {
            storage = data
        }
    }

    func clearAllDataAsync() async throws { storage = Data() }
    func currentStorage() -> Data { storage }
}
