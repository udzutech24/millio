import CoreData
import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import millio

private enum AcceptedV6FixtureMigrationPlan: SchemaMigrationPlan {
    static let schemas: [any VersionedSchema.Type] = [AppSchemaV5.self, AppSchemaV6.self]
    static let stages: [MigrationStage] = [
        .lightweight(fromVersion: AppSchemaV5.self, toVersion: AppSchemaV6.self)
    ]
}

private final class HistoricalValuationV7FixtureBundleToken {}

@Suite("Historical valuation V7 schema", .serialized)
struct HistoricalValuationV7SchemaTests {
    @Test("Checked-in accepted V6 fixture has fixed bytes and migrates to V7") @MainActor
    func checkedInAcceptedV6FixtureMigratesToV7() throws {
        let source = try #require(Self.fixtureURL(named: "accepted-product-v6.store"))
        let digest = SHA256.hash(data: try Data(contentsOf: source))
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(digest == "a2ab81a3328d29d22de2235a7624b10aa3da08e40e8783616ac6d2781d85007a")

        let copied = try Self.copyFixture(named: "accepted-product-v6.store")
        defer { try? FileManager.default.removeItem(at: copied.directoryURL) }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: copied.storeURL)
        #expect(metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["6.0.0"])

        let container = try AppMigrationPlan.makeContainer(configuration: ModelConfiguration(
            "accepted_v6_binary_to_v7_\(UUID().uuidString)",
            url: copied.storeURL,
            cloudKitDatabase: .none
        ))
        let accounts = try container.mainContext.fetch(FetchDescriptor<Account>())
        #expect(accounts.count == 2)
        #expect(accounts.contains { $0.productType == .marketStock && $0.marketMeta?.symbol == "AAPL" })
        #expect(accounts.contains { $0.productType == .unknownLegacy && $0.productMigrationReason == "ambiguous_cash" })
    }

    @Test("V7 Account revision columns are optional and close storage is additive")
    func additiveV7Shape() throws {
        let schema = Schema(AppSchemaV7.models, version: AppSchemaV7.versionIdentifier)
        let account = try #require(schema.entities.first(where: { $0.name == "Account" }))
        #expect(try #require(account.attributesByName["valuationMembershipRevision"]).isOptional)
        #expect(try #require(account.attributesByName["valuationFinancialRevision"]).isOptional)
        #expect(try #require(account.attributesByName["valuationEventRevision"]).isOptional)
        #expect(schema.entities.contains(where: { $0.name == "HistoricalPortfolioValuation" }))

        let v6Names = Set(AppSchemaV6.models.map(Self.entityName))
        #expect(!v6Names.contains("HistoricalPortfolioValuation"))
        let frozenV6Account = try #require(
            Schema(AppSchemaV6.models, version: AppSchemaV6.versionIdentifier)
                .entities.first(where: { $0.name == "Account" })
        )
        #expect(frozenV6Account.attributesByName["valuationMembershipRevision"] == nil)
        #expect(frozenV6Account.attributesByName["valuationFinancialRevision"] == nil)
        #expect(frozenV6Account.attributesByName["valuationEventRevision"] == nil)
    }

    @Test("Real V5 becomes accepted on-disk V6, then migrates to V7 without source rewrite") @MainActor
    func realAcceptedV6FixtureMigratesToV7() throws {
        let copied = try Self.copyFixture(named: "pre-product-v5.store")
        defer { try? FileManager.default.removeItem(at: copied.directoryURL) }

        let cashID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let marketID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let eventIDsBeforeV7: Set<UUID>

        do {
            let v6Schema = Schema(versionedSchema: AppSchemaV6.self)
            let configuration = ModelConfiguration(
                "accepted_v6_\(UUID().uuidString)",
                schema: v6Schema,
                url: copied.storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(
                for: v6Schema,
                migrationPlan: AcceptedV6FixtureMigrationPlan.self,
                configurations: [configuration]
            )
            let context = container.mainContext
            let accounts = try context.fetch(FetchDescriptor<AppSchemaV6.Account>())
            let events = try context.fetch(FetchDescriptor<AppSchemaV6.AccountEvent>())
            let snapshots = try context.fetch(FetchDescriptor<AppSchemaV6.AccountDailySnapshot>())

            #expect(accounts.count == 2)
            #expect(events.count == 2)
            #expect(snapshots.count == 1)
            #expect(accounts.first(where: { $0.id == cashID })?.name == "Ambiguous cash")
            #expect(accounts.first(where: { $0.id == cashID })?.note == "pre-product-v5")
            #expect(accounts.first(where: { $0.id == marketID })?.marketMeta?.symbol == "AAPL")
            #expect(accounts.allSatisfy { $0.productTypeRaw == nil && $0.productMigrationReason == nil })

            // Persist an honestly accepted Phase 1P V6 identity before V7 opens the store. This
            // proves that the V6→V7 boundary preserves product ownership instead of merely proving
            // that nil optional columns survive the migration.
            let cash = try #require(accounts.first(where: { $0.id == cashID }))
            cash.productTypeRaw = AccountProductType.unknownLegacy.rawValue
            cash.productMigrationReason = "ambiguous_cash"
            let market = try #require(accounts.first(where: { $0.id == marketID }))
            market.productTypeRaw = AccountProductType.marketStock.rawValue
            try context.save()
            eventIDsBeforeV7 = Set(events.map(\.id))
        }

        let acceptedV6Metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            type: .sqlite,
            at: copied.storeURL
        )
        #expect(acceptedV6Metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["6.0.0"])

        let configuration = ModelConfiguration(
            "accepted_v6_to_v7_\(UUID().uuidString)",
            url: copied.storeURL,
            cloudKitDatabase: .none
        )
        let container = try AppMigrationPlan.makeContainer(configuration: configuration)
        let context = container.mainContext
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let events = try context.fetch(FetchDescriptor<AccountEvent>())
        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        let prices = try context.fetch(FetchDescriptor<HistoricalAssetPrice>())
        let closes = try context.fetch(FetchDescriptor<HistoricalPortfolioValuation>())

        #expect(accounts.count == 2)
        #expect(events.count == 2)
        #expect(snapshots.count == 1)
        #expect(prices.count == 1)
        #expect(closes.isEmpty)
        #expect(Set(events.map(\.id)) == eventIDsBeforeV7)

        let cash = try #require(accounts.first(where: { $0.id == cashID }))
        #expect(cash.name == "Ambiguous cash")
        #expect(cash.note == "pre-product-v5")
        #expect(cash.productType == .unknownLegacy)
        #expect(cash.productMigrationReason == "ambiguous_cash")
        #expect(cash.valuationMembershipRevision == nil)
        #expect(cash.valuationFinancialRevision == nil)
        #expect(cash.valuationEventRevision == nil)

        let market = try #require(accounts.first(where: { $0.id == marketID }))
        #expect(market.productType == .marketStock)
        #expect(market.productMigrationReason == nil)
        #expect(market.marketMeta?.symbol == "AAPL")
        #expect(events.contains(where: { $0.account?.id == marketID && $0.type == .buy }))
        #expect(snapshots.first?.account?.id == cashID)
        #expect(prices.first?.symbol == "AAPL")
    }

    private static func copyFixture(named fixtureName: String) throws -> (
        directoryURL: URL,
        storeURL: URL
    ) {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent("valuation_v7_fixture_\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let storeURL = directoryURL.appendingPathComponent(fixtureName)

        do {
            for suffix in ["", "-wal", "-shm"] {
                let resourceName = fixtureName + suffix
                guard let sourceURL = fixtureURL(named: resourceName) else {
                    if suffix.isEmpty { throw FixtureError.missingResource(resourceName) }
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
        let bundle = Bundle(for: HistoricalValuationV7FixtureBundleToken.self)
        let candidates = [
            bundle.resourceURL?.appendingPathComponent("Fixtures/\(resourceName)"),
            bundle.resourceURL?.appendingPathComponent(resourceName)
        ]
        if let direct = candidates.compactMap({ $0 }).first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) {
            return direct
        }
        guard let root = bundle.resourceURL,
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
              ) else { return nil }
        return enumerator.compactMap { $0 as? URL }.first(where: {
            $0.lastPathComponent == resourceName
        })
    }

    private static func entityName(_ type: any PersistentModel.Type) -> String {
        String(describing: type).components(separatedBy: ".").last ?? String(describing: type)
    }

    private enum FixtureError: Error {
        case missingResource(String)
        case outputAlreadyExists(String)
    }
}
