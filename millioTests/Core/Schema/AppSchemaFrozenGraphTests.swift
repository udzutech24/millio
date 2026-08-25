import XCTest
import CoreData
import SwiftData
@testable import millio

/// Сторож замороженного AccountsCore-графа версий V7/V8/V9.
///
/// SwiftData опознаёт стор на диске ПО CHECKSUM сущностей, а не по записанному идентификатору версии.
/// `Account.depositMeta` — composite attribute, поэтому любое поле, добавленное в `DepositMeta`,
/// меняет checksum `Account` во ВСЕХ версиях схемы, которые ссылаются на продакшн-модель, — и стор
/// пользователя перестаёт соответствовать хоть какой-нибудь версии плана (NSCocoaErrorDomain 134504,
/// «Cannot use staged migration with an unknown model version»).
///
/// Если этот тест покраснел — значит замороженные декларации в `AppSchemaV7AccountsCoreModels.swift`
/// поехали вслед за продакшн-моделями. Чинить надо ИХ, а не константу: константа снята с реального
/// стора V9 до введения V10 и переписывается только вместе с новой заморозкой.
final class AppSchemaFrozenGraphTests: XCTestCase {

    /// Хеш сущности `Account`, снятый со схемы V9 до добавления `DepositMeta.isTaxable`.
    private static let frozenAccountHash = "BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss="

    private func accountVersionHash(for schema: Schema) throws -> String {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-hash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("probe.store")

        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        _ = try ModelContainer(for: schema, configurations: [configuration])

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let hashes = try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        return try XCTUnwrap(hashes["Account"]).base64EncodedString()
    }

    func testFrozenGraphKeepsHistoricalAccountChecksum() throws {
        for versioned in [AppSchemaV7.self, AppSchemaV8.self, AppSchemaV9.self] as [any VersionedSchema.Type] {
            let schema = Schema(versioned.models, version: versioned.versionIdentifier)
            XCTAssertEqual(
                try accountVersionHash(for: schema),
                Self.frozenAccountHash,
                "Схема \(versioned.versionIdentifier) больше не совпадает с уже существующими сторами"
            )
        }
    }

    /// Обратная сторона того же инварианта: у V10 форма `Account` ДРУГАЯ (поле `isTaxable`),
    /// поэтому она обязана иметь свой checksum — иначе миграция была бы бессмысленной.
    func testCurrentSchemaIntroducesNewAccountChecksum() throws {
        let current = Schema(AppSchemaCurrent.models, version: AppSchemaCurrent.versionIdentifier)
        XCTAssertNotEqual(try accountVersionHash(for: current), Self.frozenAccountHash)
    }

    /// Каждая версия из плана должна быть достижима стадией — иначе стор «застрянет» на полпути.
    func testMigrationPlanCoversEverySchemaVersion() {
        XCTAssertEqual(AppMigrationPlan.schemas.count, AppMigrationPlan.stages.count + 1)
        XCTAssertTrue(AppMigrationPlan.schemas.contains { $0 == AppSchemaCurrent.self })
    }
}
