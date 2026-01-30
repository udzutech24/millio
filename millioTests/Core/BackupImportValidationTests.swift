import Foundation
import Testing
import SwiftData
@testable import millio

@Suite(.serialized)
@MainActor
struct BackupImportValidationTests {
    private static let container: ModelContainer = {
        let schema = Schema([Item.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()
    
    private func makeContext() -> ModelContext {
        Self.container.mainContext
    }
    
    private func makeMetadata(modelCount: Int, schemaVersion: String = BackupMetadata.currentSchemaVersion) -> [String: Any] {
        [
            "version": ["major": BackupVersion.current.major, "minor": BackupVersion.current.minor, "patch": BackupVersion.current.patch],
            "timestamp": Date().timeIntervalSince1970,
            "schemaVersion": schemaVersion,
            "modelCount": modelCount
        ]
    }
    
    @Test("Import fails when metadata missing")
    func testMissingMetadataFails() throws {
        let payload: [String: Any] = ["models": []]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.backupCorrupted) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
    
    @Test("Import fails when unknown model type present")
    func testUnknownTypeFails() throws {
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 1),
            "models": [["_type": "UnknownType"]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.restoreFailed("Неизвестные типы моделей в backup: UnknownType")) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
    
    @Test("Import fails when schemaVersion mismatch")
    func testSchemaVersionMismatchFails() throws {
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 0, schemaVersion: "1.0"),
            "models": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.incompatibleSchemaVersion) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
    
    @Test("Import fails when modelCount mismatch")
    func testModelCountMismatchFails() throws {
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 0),
            "models": [["_type": "Item", "timestamp": Date().timeIntervalSince1970]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.backupCorrupted) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
    
    @Test("Import fails when _type missing")
    func testMissingTypeFails() throws {
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 1),
            "models": [["timestamp": Date().timeIntervalSince1970]]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.backupCorrupted) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
}
