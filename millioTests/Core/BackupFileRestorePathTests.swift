import Foundation
import Testing
import UniformTypeIdentifiers
@testable import millio

/// R3: сквозной путь «файл → данные» и безопасность деструктивной фазы (S14).
@Suite(.serialized)
struct BackupFileRestorePathTests {

    // MARK: - D5: расширения файла бэкапа

    @Test("Оба расширения распознаются как файл бэкапа")
    func testBothExtensionsRecognized() {
        // Файл владельца пришёл с legacy-расширением, а экспорт пишет новое — приложение обязано
        // открывать оба, иначе onOpenURL молча роняет файл в ветку виджет-диплинков.
        #expect(BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/millio-backup-2026-08-01-v1.9.milliobackup")))
        #expect(BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/backup.millio-backup")))
        #expect(BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/BACKUP.MILLIOBACKUP")))
        #expect(!BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/statement.csv")))
        #expect(!BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/backup.json")))
    }

    @Test("Info.plist объявляет оба расширения для com.alekseya.millio.backup")
    func testInfoPlistDeclaresBothExtensions() throws {
        // Регрессия D5: объявлено было только millio-backup, поэтому система не связывала
        // экспортируемые .milliobackup-файлы с приложением и Files показывал их недоступными.
        let url = try Self.sourceURL(for: "millio/Info.plist")
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: url),
            format: nil
        ) as? [String: Any]
        let declarations = try #require(plist?["UTExportedTypeDeclarations"] as? [[String: Any]])
        let backupType = try #require(declarations.first {
            $0["UTTypeIdentifier"] as? String == BackupFileFormat.contentType.identifier
        })
        let tags = try #require(backupType["UTTypeTagSpecification"] as? [String: Any])
        let extensions = try #require(tags["public.filename-extension"] as? [String])
        for expected in BackupFileFormat.recognizedExtensions {
            #expect(extensions.contains(expected), "Info.plist не объявляет расширение \(expected)")
        }
    }

    @Test("Имя экспортируемого файла использует то же расширение, что и импорт")
    func testExportFilenameUsesPreferredExtension() {
        #expect(BackupFileFormat.defaultExportFilename.hasSuffix(".\(BackupFileFormat.preferredExtension)"))
        #expect(BackupFileFormat.isBackupFile(URL(fileURLWithPath: "/tmp/\(BackupFileFormat.defaultExportFilename)")))
    }

    // MARK: - Путь «файл → данные» без CloudKit

    @Test("restoreFromFile восстанавливает данные при недоступном iCloud")
    func testRestoreFromFileWorksWithoutICloud() async throws {
        // importVersion требует облако; на свежей установке без iCloud пользователь иначе
        // не может воспользоваться собственным файлом.
        let store = MockCloudBackupStore()
        store.isAvailableResult = false
        let repository = MockDataRepository()
        repository.exportData = try Self.makePayload(types: [:])
        let manager = BackupManager(cloudStore: store, dataRepository: repository)

        let receipt = try await manager.restoreFromFile(
            try Self.makeEnvelope(types: ["Card": 2, "Investment": 3]),
            passphrase: nil
        )

        #expect(receipt.expectedModelCount == 5)
        #expect(receipt.importedModelCount == 5)
        #expect(receipt.isVerified)
        #expect(repository.importCalled)
    }

    @Test("inspectBackupFile отдаёт метаданные файла до деструктивного подтверждения")
    func testInspectBackupFileReturnsMetadata() async throws {
        let store = MockCloudBackupStore()
        let repository = MockDataRepository()
        let manager = BackupManager(cloudStore: store, dataRepository: repository)
        let file = try Self.makeEnvelope(types: ["Card": 2])

        let info = try await manager.inspectBackupFile(file)

        #expect(info.size == Int64(file.count))
        #expect(info.version == BackupVersion.current.stringValue)
        #expect(repository.clearCalled == false, "Разбор файла не имеет права трогать стор")
    }

    @Test("Пустой файл отвергается до деструктивной фазы")
    func testEmptyFileRejectedBeforeDestructivePhase() async throws {
        let repository = MockDataRepository()
        repository.exportData = try Self.makePayload(types: ["Card": 1])
        let manager = BackupManager(cloudStore: MockCloudBackupStore(), dataRepository: repository)

        await #expect(throws: AppError.self) {
            _ = try await manager.restoreFromFile(Data(), passphrase: nil)
        }
        #expect(repository.clearCalled == false)
    }

    @Test("Бэкап без моделей не стирает локальные данные")
    func testEmptyBackupFromFileNeverClearsStore() async throws {
        let repository = MockDataRepository()
        repository.exportData = try Self.makePayload(types: ["Card": 1])
        let manager = BackupManager(cloudStore: MockCloudBackupStore(), dataRepository: repository)

        await #expect(throws: Error.self) {
            _ = try await manager.restoreFromFile(try Self.makeEnvelope(types: [:]), passphrase: nil)
        }
        #expect(repository.clearCalled == false)
        #expect(repository.importCalled == false)
    }

    // MARK: - S14: safety-снимок, точка невозврата, откат

    @Test("S14: сбой импорта в середине откатывает стор к до-restore снимку")
    func testFailedImportRollsBackToSnapshot() async throws {
        let previous = try Self.makePayload(types: ["Card": 7])
        let repository = FailingImportDataRepository()
        repository.storage = previous
        repository.failNextImport = true
        let manager = BackupManager(cloudStore: MockCloudBackupStore(), dataRepository: repository)

        await #expect(throws: Error.self) {
            _ = try await manager.restoreFromFile(try Self.makeEnvelope(types: ["Card": 3]), passphrase: nil)
        }

        // Импорт бэкапа + импорт снимка; стор вернулся к прежнему состоянию.
        #expect(repository.importCalls == 2)
        #expect(repository.storage == previous, "Старые данные обязаны быть на месте после отката")
    }

    @Test("S14: провал самого отката — ошибка высшей severity с инструкцией пользователю")
    func testRollbackFailureIsCriticalAndUserReadable() async throws {
        let repository = AlwaysFailingImportDataRepository()
        repository.storage = try Self.makePayload(types: ["Card": 7])
        let manager = BackupManager(cloudStore: MockCloudBackupStore(), dataRepository: repository)

        var captured: Error?
        do {
            _ = try await manager.restoreFromFile(try Self.makeEnvelope(types: ["Card": 3]), passphrase: nil)
        } catch {
            captured = error
        }

        let failure = try #require(captured as? RestoreRollbackFailure, "Провал отката нельзя выдавать за обычный restoreFailed")
        #expect(failure.severity == .critical)
        #expect(RestoreFailureCode.rollbackFailed.severity == .critical)
        #expect(RestoreFailureCode.preRestoreSnapshotFailed.severity == .recoverable)
        let message = try #require(failure.errorDescription)
        #expect(!message.isEmpty)
        #expect(message != failure.underlyingDescription, "Пользователю нужен текст «что делать», а не описание внутренней ошибки")
    }

    @Test("Строки пути «файл → данные» лежат в каталоге для RU/EN/zh-Hans")
    func testIncomingFileStringsAreLocalized() throws {
        let keys = [
            "backup.incoming_file.confirm.title",
            "backup.incoming_file.confirm.message",
            "backup.incoming_file.confirm.action",
            "backup.incoming_file.restoring",
            "backup.incoming_file.success.title",
            "backup.incoming_file.success.message",
            "backup.incoming_file.failure.title",
            "backup.incoming_file.too_large",
            "backup.restore.from_file.action",
            "backup.restore.failure.rollback_failed"
        ]
        for key in keys {
            for locale in [Locale(identifier: "ru"), Locale(identifier: "en"), Locale(identifier: "zh-Hans")] {
                let value = BackupL10n.tr(key, locale: locale, fallback: "")
                #expect(!value.isEmpty, "Нет перевода \(locale.identifier) для \(key)")
                #expect(value != key)
            }
            #expect(BackupL10n.hasInlineTranslation(for: key), "Ключ \(key) обязан быть в каталоге, а не только в fallback")
        }
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

    private static func sourceURL(for relativePath: String) throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory.appendingPathComponent(relativePath)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw AppError.unknown(NSError(domain: "Test", code: -1))
    }
}

/// Импорт падает ВСЕГДА — моделирует худший исход: деструктивная фаза прошла, откат тоже не удался.
final class AlwaysFailingImportDataRepository: DataRepositoryProtocol {
    var storage = Data()
    private(set) var importCalls = 0

    func exportAllData() throws -> Data { storage }

    func importAllData(_ data: Data) throws {
        importCalls += 1
        throw AppError.restoreFailed("Simulated permanent import failure")
    }

    func clearAllData() throws { storage = Data() }

    func exportAllDataAsync() async throws -> Data { try exportAllData() }
    func importAllDataAsync(_ data: Data) async throws { try importAllData(data) }
    func clearAllDataAsync() async throws { try clearAllData() }
}
