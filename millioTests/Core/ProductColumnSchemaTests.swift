import CoreData
import Foundation
import SwiftData
import Testing
@testable import millio

/// Test-only additive table used to prove both schema-order permutations without reserving the
/// current production schema identifier.
@Model
final class ProductColumnOrderProbe {
    var id: UUID = UUID()
    init(id: UUID = UUID()) { self.id = id }
}

private enum ProductColumnOrderFixtureSchema: VersionedSchema {
    static let versionIdentifier = Schema.Version(90, 0, 0)
    static let models: [any PersistentModel.Type] = AppSchemaV7.models + [
        ProductColumnOrderProbe.self
    ]
}

private enum ProductColumnsThenTableMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [
        AppSchemaV7.self,
        ProductColumnOrderFixtureSchema.self
    ]
    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV7.self, toVersion: ProductColumnOrderFixtureSchema.self)
    ]
}

private final class ProductColumnSchemaTestsBundleToken {}

@Suite("Product column schema", .serialized)
struct ProductColumnSchemaTests {
    @Test("Product columns are optional attributes owned by Account")
    func optionalAccountAttributes() throws {
        let accountEntity = try #require(
            Schema(AppSchemaV6.models, version: AppSchemaV6.versionIdentifier)
                .entities
                .first(where: { $0.name == "Account" })
        )
        let productType = try #require(accountEntity.attributesByName["productTypeRaw"])
        let migrationReason = try #require(accountEntity.attributesByName["productMigrationReason"])
        #expect(productType.isOptional)
        #expect(migrationReason.isOptional)
        #expect(AppSchemaCurrent.versionIdentifier == AppSchemaV7.versionIdentifier)
    }

    @Test("A current store with nil product columns survives relaunch and remains classifiable") @MainActor
    func nilProductColumnsRoundTripAndClassify() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("product_columns_\(UUID().uuidString).store")
        defer { Self.cleanupStore(at: storeURL) }

        do {
            let configuration = ModelConfiguration(
                "product_columns_write_\(UUID().uuidString)",
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try AppMigrationPlan.makeContainer(configuration: configuration)
            let account = Account(name: "Pre-classification", kind: .cash)
            container.mainContext.insert(account)
            try container.mainContext.save()
            #expect(account.productTypeRaw == nil)
        }

        let readConfiguration = ModelConfiguration(
            "product_columns_read_\(UUID().uuidString)",
            url: storeURL,
            cloudKitDatabase: .none
        )
        let reopened = try AppMigrationPlan.makeContainer(configuration: readConfiguration)
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<Account>()).first)
        #expect(restored.productTypeRaw == nil)
        #expect(AccountProductIdentityMigrator.migrate(restored))
        try reopened.mainContext.save()
        #expect(restored.productType == .unknownLegacy)
    }

    @Test("A real pre-product V5 store migrates through the current plan") @MainActor
    func preProductV5FixtureMigratesAutomatically() throws {
        let copied = try Self.copyFixture(named: "pre-product-v5.store")
        defer { try? FileManager.default.removeItem(at: copied.directoryURL) }

        let configuration = ModelConfiguration(
            "pre_product_v5_read_\(UUID().uuidString)",
            url: copied.storeURL,
            cloudKitDatabase: .none
        )
        let container = try AppMigrationPlan.makeContainer(configuration: configuration)
        let context = container.mainContext
        let groups = try context.fetch(FetchDescriptor<AccountGroup>())
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let events = try context.fetch(FetchDescriptor<AccountEvent>())
        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        let prices = try context.fetch(FetchDescriptor<HistoricalAssetPrice>())

        #expect(groups.count == 1)
        #expect(accounts.count == 2)
        #expect(events.count == 2)
        #expect(snapshots.count == 1)
        #expect(prices.count == 1)

        let cashID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let cash = try #require(accounts.first(where: { $0.id == cashID }))
        #expect(cash.name == "Ambiguous cash")
        #expect(cash.note == "pre-product-v5")
        #expect(cash.group?.name == "Fixture group")
        #expect(cash.productTypeRaw == nil)
        #expect(cash.productMigrationReason == nil)

        let marketID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let market = try #require(accounts.first(where: { $0.id == marketID }))
        #expect(market.name == "Fixture stock")
        #expect(market.marketMeta?.symbol == "AAPL")
        #expect(market.productTypeRaw == nil)
        #expect(market.productMigrationReason == nil)
        #expect(events.contains(where: { $0.account?.id == marketID && $0.type == .buy }))
        #expect(snapshots.first?.account?.id == cashID)
        #expect(prices.first?.symbol == "AAPL")
    }

    @Test("Production-style fresh store is V7 and opens through a future additive migration") @MainActor
    func productColumnsBeforeFutureTableOrder() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("product_before_table_\(UUID().uuidString).store")
        defer { Self.cleanupStore(at: storeURL) }

        do {
            let configuration = ModelConfiguration(
                "product_before_table_write_\(UUID().uuidString)",
                url: storeURL,
                cloudKitDatabase: .none
            )
            // Matches production: callers may omit schema, but the central factory must still
            // stamp the current versioned schema into on-disk metadata.
            let container = try AppMigrationPlan.makeContainer(configuration: configuration)
            let account = Account(name: "Classified", kind: .bankAccount, productType: .bankAccount)
            container.mainContext.insert(account)
            try container.mainContext.save()
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: storeURL
        )
        #expect(metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["7.0.0"])

        let targetSchema = Schema(versionedSchema: ProductColumnOrderFixtureSchema.self)
        let readConfiguration = ModelConfiguration(
            "product_before_table_read_\(UUID().uuidString)",
            schema: targetSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let reopened = try ModelContainer(
            for: targetSchema,
            migrationPlan: ProductColumnsThenTableMigrationPlan.self,
            configurations: [readConfiguration]
        )
        let restored = try #require(reopened.mainContext.fetch(FetchDescriptor<Account>()).first)
        #expect(restored.productType == .bankAccount)
        #expect(try reopened.mainContext.fetch(FetchDescriptor<ProductColumnOrderProbe>()).isEmpty)
    }

    @Test("A real table-first store accepts product columns additively") @MainActor
    func futureTableBeforeProductColumnsOrder() throws {
        let copied = try Self.copyFixture(named: "pre-product-table-first.store")
        defer { try? FileManager.default.removeItem(at: copied.directoryURL) }

        let targetSchema = Schema(versionedSchema: ProductColumnOrderFixtureSchema.self)
        let configuration = ModelConfiguration(
            "table_first_read_\(UUID().uuidString)",
            schema: targetSchema,
            url: copied.storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: targetSchema,
            configurations: [configuration]
        )
        let accounts = try container.mainContext.fetch(FetchDescriptor<Account>())
        let probes = try container.mainContext.fetch(FetchDescriptor<ProductColumnOrderProbe>())
        let account = try #require(accounts.first)
        let probe = try #require(probes.first)

        #expect(accounts.count == 1)
        #expect(account.id == UUID(uuidString: "20000000-0000-0000-0000-000000000003"))
        #expect(account.name == "Table first cash")
        #expect(account.productTypeRaw == nil)
        #expect(account.productMigrationReason == nil)
        #expect(probes.count == 1)
        #expect(probe.id == UUID(uuidString: "50000000-0000-0000-0000-000000000001"))
    }

    private static func copyFixture(named fixtureName: String) throws -> (
        directoryURL: URL,
        storeURL: URL
    ) {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("product_fixture_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent(fixtureName)

        do {
            for suffix in ["", "-wal", "-shm"] {
                let resourceName = fixtureName + suffix
                guard let sourceURL = Self.fixtureURL(named: resourceName) else {
                    if suffix.isEmpty {
                        throw FixtureError.missingResource(resourceName)
                    }
                    continue
                }
                try fileManager.copyItem(
                    at: sourceURL,
                    to: URL(fileURLWithPath: storeURL.path + suffix)
                )
            }
            return (directoryURL, storeURL)
        } catch {
            try? fileManager.removeItem(at: directoryURL)
            throw error
        }
    }

    private static func fixtureURL(named resourceName: String) -> URL? {
        let bundle = Bundle(for: ProductColumnSchemaTestsBundleToken.self)
        let directCandidates = [
            bundle.resourceURL?.appendingPathComponent("Fixtures/\(resourceName)"),
            bundle.resourceURL?.appendingPathComponent(resourceName)
        ]
        if let direct = directCandidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            return direct
        }

        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
              ) else { return nil }
        return enumerator
            .compactMap { $0 as? URL }
            .first(where: { $0.lastPathComponent == resourceName })
    }

    private enum FixtureError: Error {
        case missingResource(String)
    }

    private static func cleanupStore(at url: URL) {
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-wal"))
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: url.path + "-shm"))
    }
}
