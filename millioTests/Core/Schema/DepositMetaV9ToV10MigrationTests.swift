import XCTest
import CoreData
import SwiftData
@testable import millio

/// Регрессия миграции V9 → V10 на вкладе, созданном ДО тега `isTaxable` и шаговой капитализации.
///
/// Проверяется именно МИГРАЦИЯ, а не round-trip на текущей схеме: стор физически пишется
/// замороженными декларациями V9 (`AppSchemaV7.Account` с `FrozenDepositMeta`, в котором поля
/// `isTaxable` нет вовсе), затем тот же файл открывается планом миграции. Тест дополнительно
/// пиннит checksum сущности `Account` до и после — если он совпал, значит стор писался уже новой
/// формой и проверка была бы фиктивной.
final class DepositMetaV9ToV10MigrationTests: XCTestCase {

    /// Хеш `Account` в форме V7–V9 (та же константа, что сторожит `AppSchemaFrozenGraphTests`).
    private static let frozenAccountHash = "BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss="

    private var storeDirectory: URL!

    override func setUpWithError() throws {
        storeDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("deposit-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDirectory)
        storeDirectory = nil
    }

    func testMonthlyDepositKeepsRateCapitalizationAndAmountAcrossMigration() throws {
        let url = storeDirectory.appendingPathComponent("legacy-deposit.store")
        let accountID = UUID()
        let opening = Date(timeIntervalSince1970: 1_735_689_600) // 2025-01-01 UTC
        let termEnd = opening.addingTimeInterval(365 * 86_400)
        let openingBalance = Decimal(string: "250000.55")!
        let rate = Decimal(string: "12.5")!

        try writeLegacyV9Store(
            at: url, accountID: accountID, opening: opening, termEnd: termEnd,
            openingBalance: openingBalance, rate: rate
        )

        // Стор действительно старой формы: иначе миграции бы не было и тест ничего не доказывал.
        XCTAssertEqual(try accountVersionHash(at: url), Self.frozenAccountHash)

        let migrated = try openMigratedStore(at: url)
        defer { _ = migrated }
        let context = ModelContext(migrated)
        let accounts = try context.fetch(FetchDescriptor<Account>())
        XCTAssertEqual(accounts.count, 1)
        let account = try XCTUnwrap(accounts.first)
        let meta = try XCTUnwrap(account.depositMeta)

        // Ставка, периодичность и сумма — без потерь.
        XCTAssertEqual(meta.rate, rate)
        XCTAssertEqual(meta.capitalization, .monthly)
        XCTAssertEqual(meta.capitalization.rawValue, "monthly")
        XCTAssertEqual(meta.payoutDay, 15)
        XCTAssertEqual(meta.earlyClosePenalty, Decimal(string: "0.5")!)
        XCTAssertEqual(meta.termEnd?.timeIntervalSince1970, termEnd.timeIntervalSince1970)
        XCTAssertTrue(meta.allowsTopUp)
        XCTAssertTrue(meta.allowsEarlyClose)
        XCTAssertTrue(meta.remindEnd)
        XCTAssertFalse(meta.autoRollover)

        // Новое поле у старой записи — именно `nil` («не размечен»), а не `false` и не ошибка декода.
        XCTAssertNil(meta.isTaxable)

        XCTAssertEqual(account.id, accountID)
        XCTAssertEqual(account.currency, "RUB")
        XCTAssertEqual(account.productType, .deposit)
        let events = account.events ?? []
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.amount, openingBalance)
        XCTAssertEqual(
            AccountBalanceEngine.balanceAt(events: events, kind: .deposit, on: opening),
            openingBalance
        )

        // Обратная сторона: форма `Account` после миграции ДРУГАЯ — файл реально переехал на V10.
        XCTAssertNotEqual(try accountVersionHash(at: url), Self.frozenAccountHash)
    }

    // MARK: - Служебное

    /// Пишет стор ровно в том виде, в каком он лежал у пользователя на V9: замороженные декларации,
    /// `DepositMeta` без `isTaxable`, идентификатор версии 9.0.0 на диске.
    private func writeLegacyV9Store(
        at url: URL,
        accountID: UUID,
        opening: Date,
        termEnd: Date,
        openingBalance: Decimal,
        rate: Decimal
    ) throws {
        let schema = Schema(AppSchemaV9.models, version: AppSchemaV9.versionIdentifier)
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        let account = AppSchemaV7.Account(
            id: accountID,
            name: "Вклад на старой схеме",
            kindRaw: AccountKind.deposit.rawValue,
            currency: "RUB",
            createdAt: opening
        )
        account.productTypeRaw = AccountProductType.deposit.rawValue
        account.depositMeta = AppSchemaV7.FrozenDepositMeta(
            rate: rate,
            capitalization: .monthly,
            termEnd: termEnd,
            payoutDay: 15,
            allowsTopUp: true,
            allowsEarlyClose: true,
            earlyClosePenalty: Decimal(string: "0.5")!,
            remindEnd: true,
            autoRollover: false
        )
        context.insert(account)

        let event = AppSchemaV7.AccountEvent(
            account: account,
            date: opening,
            createdAt: opening,
            dayKey: AccountEvent.dayKey(for: opening),
            typeRaw: AccountEventType.openingBalance.rawValue
        )
        event.amount = openingBalance
        context.insert(event)

        try context.save()
    }

    private func openMigratedStore(at url: URL) throws -> ModelContainer {
        try AppMigrationPlan.makeContainer(
            configuration: ModelConfiguration(url: url, cloudKitDatabase: .none)
        )
    }

    private func accountVersionHash(at url: URL) throws -> String {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let hashes = try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        return try XCTUnwrap(hashes["Account"]).base64EncodedString()
    }
}
