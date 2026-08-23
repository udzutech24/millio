//
//  RecoveryEndToEndIntegrationTests.swift
//  millioTests
//
//  R6 — интеграционный гейт переработки recovery.
//
//  Отличие от юнит-сюит R1–R5: здесь НЕТ моков репозитория. Реальный `DataRepository` поверх
//  in-memory `ModelContainer` и реальный файл бэкапа владельца (1673 модели, схема 2.0) —
//  проверяется не «метод не бросил ошибку», а что данные ФИЗИЧЕСКИ лежат в сторе и читаются
//  теми же fetch-запросами, что и в приложении.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct RecoveryEndToEndIntegrationTests {

    // MARK: - A1: файл → импорт → verified restore → данные в репозитории

    @Test("Сквозной путь: файл владельца → restoreFromFile → 1673 модели читаются из репозитория")
    func testOwnerFileRestoreLandsInRepository() async throws {
        let environment = try Self.makeEnvironment()
        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )

        let receipt = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)

        // 1. Receipt — verified, счётчики сошлись.
        #expect(receipt.expectedModelCount == 1673)
        #expect(receipt.importedModelCount == 1673)
        #expect(receipt.isVerified)
        #expect(receipt.missingTypes.isEmpty)

        // 2. Данные действительно в сторе: repository-путь, а не receipt.
        let context = environment.container.mainContext
        let accounts = try context.fetch(FetchDescriptor<Account>())
        let transactions = try context.fetch(FetchDescriptor<CashflowTransaction>())
        let investments = try context.fetch(FetchDescriptor<Investment>())

        #expect(accounts.count == receipt.importedByType["Account"])
        #expect(transactions.count == receipt.importedByType["CashflowTransaction"])
        #expect(investments.count == receipt.importedByType["Investment"])
        #expect(accounts.isEmpty == false)
        #expect(transactions.count == 328)

        // 3. Три конкретные сущности читаемы и не пустые — импорт восстановил поля, а не только строки.
        // У 3 из 44 счетов реального бэкапа владельца имя пустое, а fetch без сортировки отдаёт
        // произвольный порядок: проверка «accounts.first.name не пуст» краснела раз в несколько
        // прогонов. Проверяем детерминированно — сколько именованных счетов доехало.
        #expect(accounts.filter { !$0.name.isEmpty }.count == 41, "Имена счетов не восстановились")
        let account = try #require(accounts.sorted { $0.id.uuidString < $1.id.uuidString }.first)
        #expect(account.currency.isEmpty == false)
        #expect(Set(accounts.map(\.id)).count == accounts.count, "Дубли Account после restore")

        let transaction = try #require(transactions.max(by: { $0.transactionDate < $1.transactionDate }))
        #expect(transaction.amount != 0)
        #expect(transaction.currency.isEmpty == false)
        #expect(transaction.uniqueID.isEmpty == false)
        #expect(Set(transactions.map(\.uniqueID)).count == transactions.count, "Дубли транзакций после restore")

        if let investment = investments.first {
            #expect(investment.name.isEmpty == false)
        }
    }

    // MARK: - A7: авто-restore на пустой базе → verified receipt → сигнал обновления в UI-слой

    @Test("Авто-restore на пустой базе: политика разрешает, receipt verified, UI получает restoreCompleted")
    func testAutoRestoreOnEmptyStorePublishesRefreshSignal() async throws {
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)

        let backupInfo = BackupInfo(date: Date(), size: 137_362, version: "2.0")
        let decision = LaunchRecoveryPolicy.evaluate(
            LaunchRecoveryPolicy.Input(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                isGuestScope: false
            )
        )
        #expect(decision.allowsAutomaticRestore, "Пустой user-scope с бэкапом обязан идти в авто-restore")

        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        store.backupRecordNamesForRestore = ["snapshot-owner"]
        store.downloadDataByRecordName["snapshot-owner"] = try Self.ownerBackupFixture()
        let manager = BackupManager(cloudStore: store, dataRepository: environment.repository)

        let observer = RestoreEventObserver()
        defer { observer.stop() }

        let receipt = try await manager.restoreLatest(passphrase: nil)

        #expect(receipt.isVerified)
        #expect(receipt.importedModelCount == 1673)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == 328)
        #expect(observer.sawRestoreCompleted, "UI-слой обязан получить сигнал обновления без перезапуска")
        #expect(observer.sawRestoreFailed == false)
    }

    // MARK: - S13: несовместимая схема отсекается ДО деструктивной фазы

    @Test("Несовместимая схема отвергается до очистки стора — локальные данные целы")
    func testIncompatibleSchemaRejectedBeforeDestructivePhase() async throws {
        // Регрессия S13: проверка схемы жила только внутри importAllData, то есть срабатывала уже
        // ПОСЛЕ clearAllDataAsync() — данные спасал лишь откат.
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        context.insert(
            CashflowTransaction(
                transactionType: .expense,
                amount: 4_200,
                currency: "RUB",
                transactionDate: Date(timeIntervalSince1970: 1_700_000_000)
            )
        )
        try context.save()

        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )

        await #expect(throws: AppError.incompatibleSchemaVersion) {
            _ = try await manager.restoreFromFile(
                try Self.makeEnvelope(
                    models: [["_type": "Card", "id": "card-1"]],
                    schemaVersion: "99.0"
                ),
                passphrase: nil
            )
        }

        let survivors = try context.fetch(FetchDescriptor<CashflowTransaction>())
        #expect(survivors.count == 1, "Отказ по схеме не имеет права стирать локальные данные")
        #expect(survivors.first?.amount == 4_200)
    }

    @Test("Провал проверки на пустом бэкапе не публикует сигнал обновления в UI")
    func testUnverifiedRestoreDoesNotSignalRefresh() async throws {
        let environment = try Self.makeEnvironment()
        let store = MockCloudBackupStore()
        store.isAvailableResult = true
        let manager = BackupManager(cloudStore: store, dataRepository: environment.repository)

        let observer = RestoreEventObserver()
        defer { observer.stop() }

        await #expect(throws: Error.self) {
            _ = try await manager.restoreFromFile(try Self.emptyEnvelope(), passphrase: nil)
        }

        #expect(observer.sawRestoreCompleted == false, "Успех не имеет права публиковаться без verified-receipt")
        #expect(observer.sawRestoreFailed)
    }

    // MARK: - S14: неуспешный импорт → откат → прежние данные на месте (реальный стор)

    @Test("S14 на реальном сторе: провал восстановления возвращает данные владельца без потерь")
    func testFailedRestoreLeavesOwnerDataIntact() async throws {
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )

        // Исходное состояние = реальные данные владельца.
        _ = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)
        let accountsBefore = try context.fetch(FetchDescriptor<Account>()).count
        let transactionsBefore = try context.fetch(FetchDescriptor<CashflowTransaction>()).count
        let investmentsBefore = try context.fetch(FetchDescriptor<Investment>()).count
        #expect(accountsBefore > 0)
        #expect(transactionsBefore == 328)

        // Битый файл: точка невозврата пройдена быть не должна.
        await #expect(throws: Error.self) {
            _ = try await manager.restoreFromFile(try Self.corruptedEnvelope(), passphrase: nil)
        }

        #expect(try context.fetch(FetchDescriptor<Account>()).count == accountsBefore)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == transactionsBefore)
        #expect(try context.fetch(FetchDescriptor<Investment>()).count == investmentsBefore)
    }

    // MARK: - S16: смена scope в середине restore

    @Test("S16 на реальном сторе: restore завершился после свопа аккаунта — успех не публикуется в чужой scope")
    func testScopeSwitchDuringRestoreDoesNotPublishForeignSuccess() async throws {
        let environment = try Self.makeEnvironment()
        let gate = LaunchRecoveryGate()
        let appState = AppState()
        appState.lifecycle = .autoRestoring

        let token = try #require(gate.beginEvaluation(scopeKey: "user_A"))
        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )

        // Пользователь вышел и вошёл другим аккаунтом, пока шёл restore аккаунта A.
        gate.bumpGeneration()
        _ = gate.beginEvaluation(scopeKey: "user_B")
        appState.lifecycle = .ready

        let receipt = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)

        // Восстановление технически прошло, но публиковать его в scope B нельзя.
        #expect(receipt.isVerified)
        #expect(gate.shouldPublishRestoreOutcome(for: token) == false)
        if gate.shouldPublishRestoreOutcome(for: token) {
            appState.lifecycle = .restoring
        }
        #expect(appState.lifecycle == .ready, "Устаревший restore аккаунта A не имеет права менять scope B")
    }

    // MARK: - Импорт при НЕпустой базе: подтверждение обязательно, отказ ничего не меняет

    @Test("Разбор файла при непустой базе не трогает данные: отказ пользователя оставляет всё на месте")
    func testDeclinedImportOnNonEmptyStoreChangesNothing() async throws {
        let environment = try Self.makeEnvironment()
        let context = environment.container.mainContext
        let manager = BackupManager(
            cloudStore: Self.offlineCloudStore(),
            dataRepository: environment.repository
        )

        _ = try await manager.restoreFromFile(try Self.ownerBackupFixture(), passphrase: nil)
        let accountsBefore = try context.fetch(FetchDescriptor<Account>()).map(\.id).sorted { $0.uuidString < $1.uuidString }
        let transactionsBefore = try context.fetch(FetchDescriptor<CashflowTransaction>()).count

        // Пришёл ЧУЖОЙ файл: единственное, что делает UI до подтверждения, — inspectBackupFile.
        let incoming = try await Self.foreignBackupFile()
        let info = try await manager.inspectBackupFile(incoming)
        #expect(info.size == Int64(incoming.count))

        // Пользователь нажал «Отмена» — restore не вызывается, стор обязан быть нетронут.
        let accountsAfter = try context.fetch(FetchDescriptor<Account>()).map(\.id).sorted { $0.uuidString < $1.uuidString }
        #expect(accountsAfter == accountsBefore)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == transactionsBefore)

        // А подтверждение — уже деструктивно и заменяет данные (симметричная половина сценария).
        let receipt = try await manager.restoreFromFile(incoming, passphrase: nil)
        #expect(receipt.isVerified)
        #expect(try context.fetch(FetchDescriptor<CashflowTransaction>()).count == 2)
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty, "Чужой бэкап обязан заменить данные, а не слиться с ними")
    }

    // MARK: - Окружение

    /// Реестр типов моделей глобален — сюита обязана вернуть его в исходное состояние,
    /// иначе регистрации протекают в соседние сюиты полного прогона.
    private final class Environment {
        let container: ModelContainer
        let repository: DataRepository
        private let registryState: ModelTypeRegistry.State

        init(container: ModelContainer, repository: DataRepository, registryState: ModelTypeRegistry.State) {
            self.container = container
            self.repository = repository
            self.registryState = registryState
        }

        deinit {
            ModelTypeRegistry.shared.restoreState(registryState)
        }
    }

    private static func makeEnvironment() throws -> Environment {
        let registryState = ModelTypeRegistry.shared.captureState()
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
        return Environment(
            container: container,
            repository: DataRepository(modelContext: container.mainContext, modelContainer: container),
            registryState: registryState
        )
    }

    private static func offlineCloudStore() -> MockCloudBackupStore {
        let store = MockCloudBackupStore()
        store.isAvailableResult = false
        return store
    }

    private static func ownerBackupFixture() throws -> Data {
        try Data(contentsOf: sourceURL(for: "millioTests/Fixtures/owner-backup-1673-models.milliobackup"))
    }

    /// «Чужой файл» для сценария подтверждения: реальный экспорт другого стора с двумя транзакциями.
    /// Собран экспортёром приложения, а не руками, — иначе проверялась бы валидация формата,
    /// а не сам сценарий перезаписи.
    private static func foreignBackupFile() async throws -> Data {
        let foreign = try makeEnvironment()
        let context = foreign.container.mainContext
        for index in 0..<2 {
            context.insert(
                CashflowTransaction(
                    transactionType: .expense,
                    amount: Double(100 + index),
                    currency: "RUB",
                    transactionDate: Date(timeIntervalSince1970: 1_700_000_000)
                )
            )
        }
        try context.save()
        return try await foreign.repository.exportAllDataAsync()
    }

    private static func emptyEnvelope() throws -> Data {
        try makeEnvelope(models: [])
    }

    /// Envelope с корректным заголовком, но нечитаемым payload — импорт обязан упасть уже после
    /// снятия snapshot, то есть проверяется именно откат, а не ранняя валидация.
    private static func corruptedEnvelope() throws -> Data {
        let payload = Data("{\"models\": [ NOT JSON".utf8)
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(timeIntervalSince1970: 0),
            schemaVersion: BackupMetadata.currentSchemaVersion,
            modelCount: 3
        )
        let header = BackupEnvelopeHeader(
            formatVersion: BackupEnvelopeHeader.currentFormatVersion,
            metadata: metadata,
            compression: nil,
            encryption: nil
        )
        return try BackupEnvelope.pack(header: header, payload: payload)
    }

    private static func makeEnvelope(
        models: [[String: Any]],
        schemaVersion: String = BackupMetadata.currentSchemaVersion
    ) throws -> Data {
        let metadata = BackupMetadata(
            version: .current,
            timestamp: Date(timeIntervalSince1970: 0),
            schemaVersion: schemaVersion,
            modelCount: models.count
        )
        let dict: [String: Any] = [
            "metadata": try DataRepository.metadataToDict(metadata),
            "models": models
        ]
        let payload = try JSONSerialization.data(withJSONObject: dict)
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
        throw NSError(
            domain: "RecoveryEndToEndIntegrationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Не найден файл: \(relativePath)"]
        )
    }
}

/// Подписчик EventBus: «UI-слой получил сигнал обновления» проверяется через ту же шину,
/// на которую подписаны CashflowViewModel/FinanceViewModel/FinanceDynamicsViewModel.
///
/// Подписка ЗАЩИЩЁННАЯ: параллельные сюиты (`CashflowViewModelTests`, `FinanceViewModelTests`,
/// `FinanceLifecycleHarness`) зовут `EventBus.shared.removeAllSubscribers()` для своей изоляции
/// и сносили этого наблюдателя посреди его же операции — событие терялось, тест краснел ложно.
@MainActor
private final class RestoreEventObserver {
    private var token: UUID?
    private(set) var sawRestoreCompleted = false
    private(set) var sawRestoreFailed = false

    init() {
        token = EventBus.shared.subscribeProtected { [weak self] event in
            guard let self, let backupEvent = event as? BackupEvent else { return }
            switch backupEvent {
            case .restoreCompleted: self.sawRestoreCompleted = true
            case .restoreFailed: self.sawRestoreFailed = true
            default: break
            }
        }
    }

    func stop() {
        if let token {
            EventBus.shared.unsubscribe(token)
        }
        token = nil
    }
}
