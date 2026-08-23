import Foundation
import Testing
@testable import millio

/// S3: файл из Files, открытый при ЗАКРЫТОМ приложении, приходит раньше готовности DI.
/// Раньше `handle()` потреблял URL до проверки `backupManager` — файл терялся, пользователь
/// получал ложное «iCloud недоступен».
@Suite(.serialized)
struct IncomingBackupFileIntakeTests {

    @Test("Холодный старт: файл не теряется, пока DI не готов")
    @MainActor
    func testIncomingFileSurvivesUntilDependenciesAreReady() async throws {
        let url = try Self.writeBackupFile(types: ["Card": 2, "Investment": 3])
        defer { try? FileManager.default.removeItem(at: url) }

        let appState = AppState()
        appState.pendingIncomingBackupURL = url

        // Фаза 1: DIContainer ещё не собран (millioApp присваивает его позже старта сцены).
        let beforeReady = IncomingBackupFileIntake(appState: appState, backupManager: nil)
        guard case .deferredUntilReady = await beforeReady.intake(url) else {
            Issue.record("До готовности DI приём обязан откладываться, а не падать в ошибку")
            return
        }
        #expect(
            appState.pendingIncomingBackupURL == url,
            "URL потреблён до готовности приложения — файл потерян"
        )

        // Фаза 2: DI готов, повторная попытка доводит файл до подтверждения восстановления.
        let manager = BackupManager(cloudStore: MockCloudBackupStore(), dataRepository: MockDataRepository())
        let afterReady = IncomingBackupFileIntake(appState: appState, backupManager: manager)
        guard case .prepared(let file) = await afterReady.intake(url) else {
            Issue.record("После готовности DI файл обязан дойти до предложения восстановления")
            return
        }
        #expect(file.info.size == Int64(try Data(contentsOf: url).count))
        #expect(appState.pendingIncomingBackupURL == nil, "Обработанный URL обязан быть потреблён")
    }

    @Test("Недоступный iCloud не мешает приёму файла")
    @MainActor
    func testIntakeWorksWithUnavailableCloud() async throws {
        let url = try Self.writeBackupFile(types: ["Card": 1])
        defer { try? FileManager.default.removeItem(at: url) }

        let store = MockCloudBackupStore()
        store.isAvailableResult = false
        let appState = AppState()
        appState.pendingIncomingBackupURL = url
        let intake = IncomingBackupFileIntake(
            appState: appState,
            backupManager: BackupManager(cloudStore: store, dataRepository: MockDataRepository())
        )

        guard case .prepared = await intake.intake(url) else {
            Issue.record("Путь «файл → данные» не имеет права зависеть от облака")
            return
        }
    }

    // MARK: - Потолок размера входящего файла

    @Test("Файл сверх потолка отвергается по размеру, а не чтением в память")
    func testOversizedFileIsRejectedBeforeReading() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("oversized-\(UUID().uuidString).milliobackup")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        // Разреженный файл: реального места на диске не занимает, но .fileSizeKey отдаёт полный размер.
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(IncomingBackupFileIntake.maxFileSizeBytes) + 1)
        try handle.close()

        var thrown: Error?
        #expect(throws: (any Error).self) {
            do {
                _ = try IncomingBackupFileIntake.readFile(at: url)
            } catch {
                thrown = error
                throw error
            }
        }
        let message = RestoreErrorPresenter.userMessage(for: try #require(thrown))
        #expect(message == BackupL10n.tr("backup.incoming_file.too_large", fallback: ""))
        #expect(!message.isEmpty)
    }

    @Test("Файл в пределах потолка читается целиком")
    func testFileWithinLimitIsRead() throws {
        let url = try Self.writeBackupFile(types: ["Card": 1])
        defer { try? FileManager.default.removeItem(at: url) }
        let data = try IncomingBackupFileIntake.readFile(at: url)
        #expect(data.count > 0)
        #expect(data == (try Data(contentsOf: url)))
    }

    // MARK: - Helpers

    private static func writeBackupFile(types: [String: Int]) throws -> URL {
        var models: [[String: Any]] = []
        for (typeName, count) in types {
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
        let payload = try JSONSerialization.data(withJSONObject: [
            "metadata": try DataRepository.metadataToDict(metadata),
            "models": models
        ])
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        let envelope = try BackupEnvelope.pack(header: header, payload: payload)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("intake-\(UUID().uuidString).milliobackup")
        try envelope.write(to: url)
        return url
    }
}
