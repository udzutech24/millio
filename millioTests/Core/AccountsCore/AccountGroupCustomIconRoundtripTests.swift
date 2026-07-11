import Foundation
import SwiftData
import Testing
@testable import millio

/// Гейт 5c.7.6: `AccountGroup.customIconName` переживает полный CloudKit backup→restore
/// (export→clear→import, инвариант 7), а старый бэкап без поля декодируется в nil без краша.
@Suite(.serialized)
@MainActor
struct AccountGroupCustomIconRoundtripTests {

    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        CurrencyFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    @Test("customIconName (SF Symbol и монограмма) переживает export→clear→import; nil остаётся nil")
    func testCustomIconNameSurvivesRoundtrip() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let symbolGroup = AccountGroup(name: "Инвестиции", colorHex: "#00AA00", order: 0)
            symbolGroup.customIconName = "bitcoinsign.circle.fill"
            context.insert(symbolGroup)

            let monogramGroup = AccountGroup(name: "Сбер", colorHex: "#21A038", order: 1)
            monogramGroup.customIconName = "monogram:СБ"
            context.insert(monogramGroup)

            // Группа без кастомной иконки — контроль, что nil не превращается в мусорную строку.
            let plainGroup = AccountGroup(name: "Прочее", order: 2)
            context.insert(plainGroup)
            try context.save()

            let backupData = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            #expect(try context.fetch(FetchDescriptor<AccountGroup>()).isEmpty)

            try repository.importAllData(backupData)

            let restored = try context.fetch(FetchDescriptor<AccountGroup>())
            #expect(restored.count == 3)
            #expect(restored.first { $0.name == "Инвестиции" }?.customIconName == "bitcoinsign.circle.fill")
            #expect(restored.first { $0.name == "Сбер" }?.customIconName == "monogram:СБ")
            #expect(restored.first { $0.name == "Прочее" }?.customIconName == nil)
        }
    }

    @Test("Старый бэкап без ключа customIconName декодируется в nil без краша")
    func testOldBackupWithoutIconDecodesToNil() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            // Запись из бэкапа, снятого ДО появления поля — ключа customIconName в словаре нет.
            let legacyDict: [String: Any] = [
                "type": "AccountGroup",
                "id": UUID().uuidString,
                "name": "Легаси-группа",
                "order": 0
            ]
            try AccountGroupImporter.import(from: legacyDict, context: context)
            try context.save()

            let restored = try context.fetch(FetchDescriptor<AccountGroup>())
            #expect(restored.count == 1)
            #expect(restored.first?.name == "Легаси-группа")
            #expect(restored.first?.customIconName == nil)
        }
    }
}
