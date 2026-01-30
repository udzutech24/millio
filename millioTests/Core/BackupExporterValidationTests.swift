import Foundation
import SwiftData
import Testing
@testable import millio

@Model
final class BadExportModel: Persistable {
    var timestamp: TimeInterval = Date().timeIntervalSince1970
    
    init() {}
    
    func export() throws -> Data {
        try JSONSerialization.data(withJSONObject: ["not-a-dict"])
    }
    
    static func `import`(_ data: Data) throws {}
}

@Suite(.serialized)
@MainActor
struct BackupExporterValidationTests {
    private static var badExportModelDefaultExporter: ((ModelContext) throws -> [[String: Any]])?
    
    private static let didRegisterBadExportModel: Void = {
        ModelTypeRegistry.shared.register(BadExportModel.self, typeName: "BadExportModel")
        badExportModelDefaultExporter = ModelTypeRegistry.shared.getBackupExporter(for: "BadExportModel")
        
        ModelTypeRegistry.shared.registerBackupExporter("BadExportModel") { _ in [] }
        ModelTypeRegistry.shared.registerBackupClearer("BadExportModel") { _ in }
    }()
    
    private func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, BadExportModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }
    
    @Test("Export fails when model export() returns non-dictionary JSON")
    func testNonDictExportFailsControlled() throws {
        _ = Self.didRegisterBadExportModel
        
        let container = makeContainer()
        let context = container.mainContext
        context.insert(BadExportModel())
        try context.save()
        
        let previousExporter = ModelTypeRegistry.shared.getBackupExporter(for: "BadExportModel")
        defer {
            ModelTypeRegistry.shared.registerBackupExporter("BadExportModel") { _ in [] }
            if let previousExporter {
                ModelTypeRegistry.shared.registerBackupExporter("BadExportModel", exporter: previousExporter)
            }
        }
        
        guard let defaultExporter = Self.badExportModelDefaultExporter else {
            throw AppError.backupFailed("BadExportModel exporter not registered")
        }
        ModelTypeRegistry.shared.registerBackupExporter("BadExportModel", exporter: defaultExporter)
        
        #expect(throws: AppError.backupFailed("Экспорт модели 'BadExportModel' вернул неожиданный формат")) {
            _ = try DataRepository.exportAllData(from: context)
        }
    }
}

