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
    
    private func makeMetadata(
        modelCount: Int,
        schemaVersion: String = BackupMetadata.currentSchemaVersion,
        version: BackupVersion = .current
    ) -> [String: Any] {
        [
            "version": ["major": version.major, "minor": version.minor, "patch": version.patch],
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
    
    @Test("Import fails when backup major version mismatch")
    func testMajorVersionMismatchFails() throws {
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 0, version: BackupVersion(major: 1, minor: 0, patch: 0)),
            "models": []
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        #expect(throws: AppError.incompatibleSchemaVersion) {
            try DataRepository.importAllData(data, into: makeContext())
        }
    }
    
    @Test("Import respects importPriority then typeName sorting")
    func testImportRespectsPriorityThenTypeNameSorting() throws {
        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        
        enum ImportOrderRecorder {
            static var calls: [String] = []
        }
        
        struct Priority0ImporterC: ModelImporter {
            static var importPriority: Int { 0 }
            static func importType() -> String { "C" }
            static func `import`(from data: [String: Any], context: ModelContext) throws {
                ImportOrderRecorder.calls.append("C")
            }
        }
        
        struct Priority1ImporterA: ModelImporter {
            static var importPriority: Int { 1 }
            static func importType() -> String { "A" }
            static func `import`(from data: [String: Any], context: ModelContext) throws {
                ImportOrderRecorder.calls.append("A")
            }
        }
        
        struct Priority1ImporterB: ModelImporter {
            static var importPriority: Int { 1 }
            static func importType() -> String { "B" }
            static func `import`(from data: [String: Any], context: ModelContext) throws {
                ImportOrderRecorder.calls.append("B")
            }
        }
        
        ModelTypeRegistry.shared.registerImporter(Priority0ImporterC.self)
        ModelTypeRegistry.shared.registerImporter(Priority1ImporterA.self)
        ModelTypeRegistry.shared.registerImporter(Priority1ImporterB.self)
        
        ImportOrderRecorder.calls = []
        
        let payload: [String: Any] = [
            "metadata": makeMetadata(modelCount: 3),
            "models": [
                ["_type": "B"],
                ["_type": "C"],
                ["_type": "A"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        try DataRepository.importAllData(data, into: makeContext())
        
        #expect(ImportOrderRecorder.calls == ["C", "A", "B"])
    }
}
