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
    private func makeContainer() -> ModelContainer {
        let schema = Schema([Item.self, BadExportModel.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }

    @Test("Export fails when model export() returns non-dictionary JSON")
    func testNonDictExportFailsControlled() throws {
        let snapshot = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(snapshot) }

        ModelTypeRegistry.shared.register(BadExportModel.self, typeName: "BadExportModel")

        let container = makeContainer()
        let context = container.mainContext
        context.insert(BadExportModel())
        try context.save()

        #expect(throws: BackupFailureCode.modelExportUnexpectedFormat("BadExportModel").appError) {
            _ = try DataRepository.exportAllData(from: context)
        }
    }
}
