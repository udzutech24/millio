import XCTest
import CoreData
import SwiftData
@testable import millio

/// Сторож замороженных исторических схем V1–V9.
///
/// SwiftData опознаёт стор на диске ПО CHECKSUM сущностей, а не по записанному идентификатору версии.
/// Composite attributes (`Account.depositMeta` и остальные `*Meta`) входят в этот checksum своими
/// полями, поэтому любое поле, добавленное в `DepositMeta`, меняет checksum `Account` во ВСЕХ
/// версиях схемы, которые ссылаются на продакшн-модель, — и стор пользователя перестаёт
/// соответствовать хоть какой-нибудь версии плана (NSCocoaErrorDomain 134504, «Cannot use staged
/// migration with an unknown model version»). Дальше срабатывает no-plan fallback и данные теряются.
///
/// Если этот тест покраснел — значит замороженные декларации поехали вслед за продакшн-моделями.
/// Чинить надо ИХ (`AppSchemaV5/V6/V7AccountsCoreModels.swift`), а не константы: константы сняты
/// с develop `a664e2c` и сверены с байтами реальных сторов-фикстур `pre-product-v5.store` (5.0.0)
/// и `accepted-product-v6.store` (6.0.0).
final class AppSchemaFrozenGraphTests: XCTestCase {

    /// Сущности, чья форма одинакова во всех версиях, где они присутствуют.
    private static let stableEntityHashes: [String: String] = [
        "AccountAppearance": "bs8fkvNg/iptT9sGmJ5lJJtJSMrH/tXe6+4vK8zJOIE=",
        "AccountAttachment":"5wPs1AU9t2gjI9MY2HdhSuowObI3jyHjJ/2W+M0a9GA=",
        "AccountDailySnapshot": "AI3BWjJIOLr0klAx1wqEJmd7q5vf75JZKxRXZm8G+UQ=",
        "AccountEvent": "EmlGFhcjmfpsopi0rUHOrE66H8gucF9tP3KeE/2xnZE=",
        "AccountGroup": "3fC1ZRhAG+Gb0X7EyZvXo09ybiIcY0uLLDL6SqSUnwk=",
        "AssetCatalogItem": "MFNLLaRkvqDyTXXJz/8iFiyR4g8aji+k/83Jb7x8Y5Q=",
        "AssetProviderMapping": "5kjjsPr9COyUcoGY2mxoyPLszRBUtScjvpxpK4QK5Ak=",
        "BudgetCategoryLimit": "YdNMBicgjUsan8NFVul3xUVVvZYIUTLzUC+gOkEgWyk=",
        "BudgetPlan": "Tf2P5GDro1p2wEwkUFYxkCBOLMclyprzDz6hXym/VQ4=",
        "Card": "K+ho9NaCs91m1KWl5LE4J90nKgFhoThCogiDf0QdGwo=",
        "Cashback": "3Hh1S+z3xtSmpZy6wY9C6eWeetNUerSTO+FG11V9NXY=",
        "CashbackCustomCategory": "SXHgCW2sAJlumeyyT1kYgOqjOiwsmQIwcFcF7E269ZA=",
        "CashflowCustomCategory": "lIfJsnQm97DFi4dpBndpin/NZK0/KvH+Y3JSgL/mX2w=",
        "CashflowMonthClosureEvent": "0rSko8Cs/vppoOnpvg3NB+RP+tcouFwbYD5hOnYgT5E=",
        "CashflowSystemCategoryOverride": "P3y0nVUFg5bcQHWS3+uOCyYiMo6q5e89XF6oktB21MA=",
        "CashflowTransaction": "PBPqL8UptR3p3k4mHAQ1PGb3+9l/POgiMvKu7rvza0c=",
        "Credit": "nUtn6QR/Tw8aM55f6z2+/mnUZeg76Jlq91xK455ur40=",
        "FinanceAccount": "fUyP7xHOLZmyTlpesG9rWhrNTYHqQTl8X+TnF6TScMk=",
        "FinanceGroup": "BnEMGV5rRS4zWfJUhrX1ft8E0b9WNzWHDuZEfgzZxIo=",
        "HistoricalAssetPrice": "O+kKZjJB/GBlOBEMglnBNhplpkDqfQHypJP+7umYuBk=",
        "HistoricalPortfolioValuation": "93A+Ieryn7aSliBGBuiigxHs1jzlZtRynhrTEEJgXQg=",
        "HistoricalRate": "cd6d9C8mT8B6hE5rm5eaKM4gYwgGScancmY+Ej27BWs=",
        "Investment": "FgboFLYvtZ2iPFdx5zp11jJDYNegccFA7RGgFwf3d04=",
        "Item": "tz+EqCETrYpwWl4jr1szrkJaRxICg51GevZadC+AOhk=",
        "RealEstateProfile": "gnszD3aSrzhhTjHuWRrkS9iRBuSU1a/ZxiCB6WfOUkw=",
        "UserSubscription": "GgtGxZcpdMUy8UdNMgVpJ/0XqKxJAp4VAFmDT7ntx5g="
    ]

    /// `Account` — единственная сущность, форма которой менялась от версии к версии:
    /// V4/V5 — до product identity, V6 — с `productTypeRaw`, V7–V9 — с valuation-ревизиями.
    private static let accountHashByVersion: [String: String] = [
        "4.0.0": "2Y6eyVdm6ZYMsMBb6L9gaLU7k6qiK1CoGyjjs9ElRD8=",
        "5.0.0": "2Y6eyVdm6ZYMsMBb6L9gaLU7k6qiK1CoGyjjs9ElRD8=",
        "6.0.0": "02wKdtQoIsrSY/+hoeRf0BQyJAGEnly56ryX8QTc2B0=",
        "7.0.0": "BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss=",
        "8.0.0": "BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss=",
        "9.0.0": "BDWJy0HN268pIbYHiNuawlUTybynWnG7Qmu7wnySOss=",
        "10.0.0": "yWZTWJU6/413j5DfgWJ96vwglPg7qQGzXwjvm0SPeWg="
    ]

    private static let historicalVersions: [any VersionedSchema.Type] = [
        AppSchemaV1.self, AppSchemaV2.self, AppSchemaV3.self,
        AppSchemaV4.self, AppSchemaV5.self, AppSchemaV6.self,
        AppSchemaV7.self, AppSchemaV8.self, AppSchemaV9.self,
        AppSchemaV10.self
    ]

    /// Checksum'ы читаются не из декларации, а из метаданных РЕАЛЬНО записанного стора —
    /// ровно тем же путём, каким SwiftData сверяет стор пользователя при открытии.
    private func entityHashes(for schema: Schema) throws -> [String: String] {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("schema-hash-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("probe.store")

        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        _ = try ModelContainer(for: schema, configurations: [configuration])

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url)
        let hashes = try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        return hashes.mapValues { $0.base64EncodedString() }
    }

    private func accountVersionHash(for schema: Schema) throws -> String {
        try XCTUnwrap(entityHashes(for: schema)["Account"])
    }

    /// Полный пин: КАЖДАЯ сущность КАЖДОЙ исторической версии обязана иметь тот же checksum,
    /// что и до появления V10. Ловит любой composite attribute, а не только `depositMeta`.
    func testEveryHistoricalEntityKeepsItsChecksum() throws {
        for versioned in Self.historicalVersions {
            let version = "\(versioned.versionIdentifier)"
            let schema = Schema(versioned.models, version: versioned.versionIdentifier)
            let actual = try entityHashes(for: schema)

            var expected = Self.stableEntityHashes.filter { actual.keys.contains($0.key) }
            if let accountHash = Self.accountHashByVersion[version] {
                expected["Account"] = accountHash
            }

            XCTAssertEqual(
                Set(actual.keys),
                Set(expected.keys),
                "Схема \(version): изменился состав сущностей"
            )
            for (entity, hash) in expected {
                XCTAssertEqual(
                    actual[entity],
                    hash,
                    "Схема \(version), сущность \(entity): checksum разошёлся с уже существующими сторами"
                )
            }
        }
    }

    /// Текущая версия (V11) — АДДИТИВНАЯ: она добавляет таблицу `AccountAppearance` и не трогает
    /// `Account`. Для такой версии корректный инвариант обратный прежнему: checksum `Account`
    /// обязан СОВПАДАТЬ с предыдущей версией. Расхождение означало бы незапланированную правку
    /// продакшн-модели — ровно тот сценарий, который даёт 134504 на сторах пользователей.
    ///
    /// ⚠️ Если следующая версия схемы всё-таки меняет `Account` — этот тест переписывается на
    /// «не равно предыдущей», а хеш предыдущей версии пинится в `accountHashByVersion`.
    /// Ослаблять его до «всегда истина» нельзя: он единственный сторож формы `Account`.
    func testCurrentAdditiveSchemaKeepsPreviousAccountChecksum() throws {
        let current = Schema(AppSchemaCurrent.models, version: AppSchemaCurrent.versionIdentifier)
        let currentHash = try accountVersionHash(for: current)
        let previousHash = try XCTUnwrap(Self.accountHashByVersion["10.0.0"])
        XCTAssertEqual(
            currentHash,
            previousHash,
            "Текущая версия заявлена как аддитивная, но форма Account изменилась — стор V10 больше не откроется"
        )
        // При этом от версий ДО V10 (там ещё не было `DepositMeta.isTaxable`) он по-прежнему отличается.
        for version in ["4.0.0", "5.0.0", "6.0.0", "7.0.0", "8.0.0", "9.0.0"] {
            XCTAssertNotEqual(currentHash, Self.accountHashByVersion[version])
        }
    }

    /// Прямая проверка аддитивности текущей версии на уровне записанного стора: все сущности
    /// предыдущей версии присутствуют с теми же checksum, а разница ровно одна — новая таблица.
    ///
    /// Baseline двигается вместе с текущей версией (V10 → V11 при переходе на V12): тест сравнивает
    /// «эта версия против предыдущей», а не против произвольной исторической.
    func testCurrentSchemaOnlyAddsNewEntityOnTopOfPreviousVersion() throws {
        let previous = try entityHashes(for: Schema(AppSchemaV11.models, version: AppSchemaV11.versionIdentifier))
        let current = try entityHashes(for: Schema(AppSchemaCurrent.models, version: AppSchemaCurrent.versionIdentifier))

        XCTAssertEqual(Set(current.keys).subtracting(previous.keys), ["LoanContract"])
        // Форма V11-таблицы уже запинена в `stableEntityHashes` — проверяем, что V12 её не сдвинула.
        // `LoanContract` попадёт туда, когда V12 станет исторической (т.е. при появлении V13):
        // пинить checksum версии, которая ещё меняется, значит ловить ложные красные.
        XCTAssertEqual(current["AccountAppearance"], Self.stableEntityHashes["AccountAppearance"])
        XCTAssertTrue(Set(previous.keys).subtracting(current.keys).isEmpty, "V12 потеряла таблицы V11")
        for (entity, hash) in previous {
            XCTAssertEqual(current[entity], hash, "V12 изменила форму сущности \(entity)")
        }
    }

    /// Каждая версия из плана должна быть достижима стадией — иначе стор «застрянет» на полпути.
    func testMigrationPlanCoversEverySchemaVersion() {
        XCTAssertEqual(AppMigrationPlan.schemas.count, AppMigrationPlan.stages.count + 1)
        XCTAssertTrue(AppMigrationPlan.schemas.contains { $0 == AppSchemaCurrent.self })
    }
}
