import Foundation
import Testing
import SwiftData
@testable import millio

/// R2: восстановление считается успешным только после пересчёта стора (RestoreReceipt).
@Suite(.serialized)
struct BackupVerifiedRestoreTests {

    // MARK: - Пересчёт моделей

    @Test("Census считает модели по типам")
    func testCensusCountsByType() throws {
        let data = try Self.makePayload(types: ["Card": 2, "Investment": 3])
        let counts = try RestoreModelCensus.counts(in: data)
        #expect(counts.total == 5)
        #expect(counts.byType["Card"] == 2)
        #expect(counts.byType["Investment"] == 3)
    }

    @Test("Census отвергает payload без models")
    func testCensusRejectsCorruptedPayload() {
        #expect(throws: AppError.backupCorrupted) {
            _ = try RestoreModelCensus.counts(in: Data("{}".utf8))
        }
    }

    @Test("Receipt: полное совпадение счётчиков = verified")
    func testReceiptVerifiedOnExactMatch() throws {
        let receipt = try RestoreModelCensus.makeReceipt(
            expectedBackup: Self.makePayload(types: ["Card": 2, "Investment": 3]),
            actualStoreExport: Self.makePayload(types: ["Card": 2, "Investment": 3])
        )
        #expect(receipt.expectedModelCount == 5)
        #expect(receipt.importedModelCount == 5)
        #expect(receipt.isVerified)
        #expect(receipt.verificationFailure == nil)
    }

    @Test("Receipt: дедупликация уменьшила счётчик, но типы на месте = verified")
    func testReceiptVerifiedWhenDeduplicationReducedCount() throws {
        let receipt = try RestoreModelCensus.makeReceipt(
            expectedBackup: Self.makePayload(types: ["Card": 4, "Investment": 3]),
            actualStoreExport: Self.makePayload(types: ["Card": 2, "Investment": 3])
        )
        #expect(receipt.isVerified)
        #expect(receipt.reducedByDeduplication == 2)
    }

    @Test("Receipt: пустой стор после импорта = провал восстановления")
    func testReceiptFailsOnEmptyStore() throws {
        let receipt = try RestoreModelCensus.makeReceipt(
            expectedBackup: Self.makePayload(types: ["Card": 2]),
            actualStoreExport: Self.makePayload(types: [:])
        )
        #expect(!receipt.isVerified)
        #expect(receipt.verificationFailure == .emptyStoreAfterImport)
    }

    @Test("Receipt: потерянный целиком тип = провал восстановления")
    func testReceiptFailsOnMissingType() throws {
        let receipt = try RestoreModelCensus.makeReceipt(
            expectedBackup: Self.makePayload(types: ["Card": 2, "Investment": 3]),
            actualStoreExport: Self.makePayload(types: ["Card": 2])
        )
        #expect(receipt.verificationFailure == .missingModelTypes(["Investment"]))
    }

    @Test("Receipt: пустой бэкап не считается успешным восстановлением")
    func testReceiptFailsOnEmptyBackup() throws {
        let receipt = try RestoreModelCensus.makeReceipt(
            expectedBackup: Self.makePayload(types: [:]),
            actualStoreExport: Self.makePayload(types: [:])
        )
        #expect(receipt.verificationFailure == .emptyBackup)
    }

    @Test("Сообщения о провале проверки лежат в каталоге для RU/EN/zh-Hans, а не в коде")
    func testVerificationFailureMessagesAreLocalized() throws {
        let catalog = try Self.stringCatalogEntries()
        for failure: RestoreVerificationFailure in [.emptyBackup, .emptyStoreAfterImport, .missingModelTypes(["Card"])] {
            let entry = try #require(
                catalog[failure.localizationKey] as? [String: Any],
                "Ключ \(failure.localizationKey) отсутствует в Localizable.xcstrings"
            )
            let localizations = try #require(entry["localizations"] as? [String: Any])
            for language in ["ru", "en", "zh-Hans"] {
                let unit = (localizations[language] as? [String: Any])?["stringUnit"] as? [String: Any]
                let value = unit?["value"] as? String
                #expect(value?.isEmpty == false, "Нет перевода \(language) для \(failure.localizationKey)")
            }
            #expect(!failure.userMessage.isEmpty)
        }
    }

    // MARK: - Путь restore целиком

    @Test("Пустой бэкап не запускает деструктивную фазу и не публикует успех")
    func testEmptyBackupNeverClearsStore() async throws {
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["snapshot-1"] = try Self.makeEnvelope(types: [:])

        let repository = MockDataRepository()
        repository.exportData = try Self.makePayload(types: ["Card": 1])
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        await #expect(throws: AppError.self) {
            _ = try await manager.restoreVersion(recordName: "snapshot-1", passphrase: nil)
        }
        #expect(repository.clearCalled == false)
        #expect(repository.importCalled == false)
    }

    @Test("Импорт без записи данных откатывается и не выдаётся за успех")
    func testUnverifiedRestoreRollsBack() async throws {
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["snapshot-1"] = try Self.makeEnvelope(types: ["Card": 3])

        // Репозиторий «проглатывает» импорт: ошибок нет, но стор остаётся пустым —
        // ровно тот сценарий, который до R2 публиковался как успешное восстановление.
        let repository = SwallowingImportDataRepository()
        repository.exportData = try Self.makePayload(types: [:])
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        await #expect(throws: AppError.self) {
            _ = try await manager.restoreVersion(recordName: "snapshot-1", passphrase: nil)
        }
        #expect(repository.rolledBack, "После неподтверждённого импорта обязан быть откат к до-restore снимку")
    }

    // MARK: - Эталонный файл владельца (1673 модели, схема 2.0)

    @MainActor
    @Test("Реальный бэкап владельца: 1673 ожидалось → 1673 импортировано, receipt verified")
    func testOwnerBackupFixtureRestoresVerified() async throws {
        let fixture = try Self.ownerBackupFixture()

        let registryState = ModelTypeRegistry.shared.captureState()
        defer { ModelTypeRegistry.shared.restoreState(registryState) }
        CurrencyFeatureRegistration.register()
        CardFeatureRegistration.register()
        CashbackFeatureRegistration.register()
        CreditFeatureRegistration.register()
        InvestmentFeatureRegistration.register()
        FinanceFeatureRegistration.register()
        CashflowFeatureRegistration.register()
        UserSubscriptionsFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()

        let container = try ModelContainer(
            for: AppSchema.create(),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let repository = DataRepository(modelContext: container.mainContext, modelContainer: container)

        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.downloadDataByRecordName["snapshot-owner"] = fixture
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        let receipt = try await manager.restoreVersion(recordName: "snapshot-owner", passphrase: nil)

        #expect(receipt.expectedModelCount == 1673)
        #expect(receipt.importedModelCount == 1673)
        #expect(receipt.isVerified)
        #expect(receipt.missingTypes.isEmpty)
        #expect(receipt.expectedByType["CashflowTransaction"] == 328)
        #expect(receipt.importedByType["CashflowTransaction"] == 328)
        #expect(receipt.expectedByType["FinanceAccount"] == 65)
        #expect(receipt.importedByType["Account"] == 44)
    }

    @MainActor
    @Test("Кешбэк, привязанный к core-счёту, импортируется после Account, а не раньше")
    func testCashbackImportsAfterAccounts() throws {
        // Регрессия: при importPriority 20 кешбэк искал Account до его импорта и ронял весь restore
        // в backupCorrupted — валидный бэкап не восстанавливался целиком.
        #expect(CashbackImporter.importPriority > AccountImporter.importPriority)
    }

    // MARK: - Helpers

    private static func makePayload(types: [String: Int]) throws -> Data {
        var models: [[String: Any]] = []
        for (typeName, count) in types.sorted(by: { $0.key < $1.key }) {
            for index in 0..<count {
                models.append(["_type": typeName, "id": "\(typeName)-\(index)"])
            }
        }
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(timeIntervalSince1970: 0),
            schemaVersion: BackupMetadata.currentSchemaVersion,
            modelCount: models.count
        )
        let dict: [String: Any] = [
            "metadata": try DataRepository.metadataToDict(metadata),
            "models": models
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    private static func makeEnvelope(types: [String: Int]) throws -> Data {
        let payload = try makePayload(types: types)
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(timeIntervalSince1970: 0),
            schemaVersion: BackupMetadata.currentSchemaVersion,
            modelCount: (try RestoreModelCensus.counts(in: payload)).total
        )
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        return try BackupEnvelope.pack(header: header, payload: payload)
    }

    private static func ownerBackupFixture() throws -> Data {
        try Data(contentsOf: sourceURL(for: "millioTests/Fixtures/owner-backup-1673-models.milliobackup"))
    }

    private static func stringCatalogEntries() throws -> [String: Any] {
        let data = try Data(contentsOf: sourceURL(for: "millio/Localizable.xcstrings"))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return try #require(json?["strings"] as? [String: Any])
    }

    private static func sourceURL(for relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "BackupVerifiedRestoreTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Не найден файл: \(relativePath)"]
        )
    }
}

/// Импорт молча ничего не пишет: воспроизводит «restore прошёл, а данных нет».
final class SwallowingImportDataRepository: DataRepositoryProtocol {
    var exportData = Data()
    private(set) var rolledBack = false
    private var importCalls = 0

    func exportAllData() throws -> Data { exportData }

    func importAllData(_ data: Data) throws {
        importCalls += 1
        // Второй импорт в рамках одной операции — это откат к до-restore снимку.
        if importCalls > 1 { rolledBack = true }
    }

    func clearAllData() throws {}

    func exportAllDataAsync() async throws -> Data { try exportAllData() }
    func importAllDataAsync(_ data: Data) async throws { try importAllData(data) }
    func clearAllDataAsync() async throws { try clearAllData() }
}
