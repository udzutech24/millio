//
//  BackupLookupOutcomeTests.swift
//  millioTests
//
//  R4: ошибка поиска бэкапа обязана отличаться от «бэкапов нет».
//

import Foundation
import Testing
import CloudKit
@testable import millio

struct BackupLookupOutcomeTests {
    // MARK: - Классификация причины

    @Test("Сетевая ошибка классифицируется как отсутствие связи, а не как «нет бэкапа»")
    func testNetworkErrorsClassified() {
        let urlError = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let ckNetwork = NSError(domain: CKErrorDomain, code: CKError.Code.networkUnavailable.rawValue)

        #expect(BackupLookupFailureReason.classify(urlError) == .network)
        #expect(BackupLookupFailureReason.classify(ckNetwork) == .network)
    }

    @Test("Отсутствие iCloud-аккаунта и троттлинг — разные причины")
    func testAccountAndThrottlingClassified() {
        let notAuthenticated = NSError(domain: CKErrorDomain, code: CKError.Code.notAuthenticated.rawValue)
        let rateLimited = NSError(domain: CKErrorDomain, code: CKError.Code.requestRateLimited.rawValue)
        let alien = NSError(domain: "com.millio.tests", code: 42)

        #expect(BackupLookupFailureReason.classify(notAuthenticated) == .iCloudUnavailable)
        #expect(BackupLookupFailureReason.classify(rateLimited) == .serviceBusy)
        #expect(BackupLookupFailureReason.classify(alien) == .unknown)
    }

    // MARK: - BackupManager

    @Test("Ошибка облака даёт .failed, а не пустой список (D8)")
    func testCloudFailureIsNotEmptyOutcome() async {
        let cloudStore = MockCloudBackupStore()
        cloudStore.listVersionsError = NSError(domain: CKErrorDomain, code: CKError.Code.networkUnavailable.rawValue)
        let manager = BackupManager(cloudStore: cloudStore, dataRepository: MockDataRepository())

        let outcome = await manager.lookupBackupVersions()

        #expect(outcome == .failed(.network))
        #expect(outcome != .empty)
        #expect(outcome.isUnresolved)
    }

    @Test("Пустое облако даёт .empty, непустое — .found")
    func testEmptyAndFoundOutcomes() async {
        let cloudStore = MockCloudBackupStore()
        let manager = BackupManager(cloudStore: cloudStore, dataRepository: MockDataRepository())

        let empty = await manager.lookupBackupVersions()
        #expect(empty == .empty)
        #expect(empty.isUnresolved == false)

        cloudStore.listedVersions = [
            BackupVersionInfo(recordName: "snapshot-1", date: Date(), size: 2048, version: "2.0", isPinned: false)
        ]
        let found = await manager.lookupBackupVersions()
        #expect(found.versions.count == 1)
        #expect(found.isUnresolved == false)
    }

    @Test("Совместимость: listBackupVersions при ошибке облака по-прежнему отдаёт пустой список")
    func testLegacyListStaysCompatible() async {
        let cloudStore = MockCloudBackupStore()
        cloudStore.listVersionsError = NSError(domain: CKErrorDomain, code: CKError.Code.notAuthenticated.rawValue)
        let manager = BackupManager(cloudStore: cloudStore, dataRepository: MockDataRepository())

        let versions = await manager.listBackupVersions()

        #expect(versions.isEmpty)
    }

    // MARK: - Таймаут и повтор

    @Test("Молчание облака дольше таймаута даёт .timedOut, а не .empty")
    func testTimeoutOutcome() async {
        let manager = SlowLookupManager(delay: .seconds(5), result: .empty)

        let outcome = await manager.lookupBackupVersions(timeout: 0.05)

        #expect(outcome == .timedOut)
    }

    @Test("Retry повторяет запрос: после провала второй вызов возвращает найденное")
    func testRetryRepeatsLookup() async {
        let manager = ScriptedLookupManager(results: [
            .failed(.network),
            .found([BackupVersionInfo(recordName: "snapshot-1", date: Date(), size: 2048, version: "2.0", isPinned: false)])
        ])

        let first = await manager.lookupBackupVersions(timeout: 1)
        let second = await manager.lookupBackupVersions(timeout: 1)

        #expect(first == .failed(.network))
        #expect(second.versions.count == 1)
        #expect(await manager.calls == 2)
    }

    @Test("Мок без своей реализации получает исход из списка версий")
    func testDefaultImplementationMapsList() async {
        let manager = MockBackupManager()

        let outcome = await manager.lookupBackupVersions()

        #expect(outcome == .empty || outcome.versions.isEmpty == false)
    }

    // MARK: - Диагностика

    @Test("Диагностическая строка различает исходы и не содержит пользовательских данных")
    func testDiagnosticSummary() {
        #expect(BackupLookupOutcome.empty.diagnosticSummary == "backup_lookup empty")
        #expect(BackupLookupOutcome.timedOut.diagnosticSummary == "backup_lookup timed_out")
        #expect(BackupLookupOutcome.failed(.network).diagnosticSummary == "backup_lookup failed=network")
    }
}

// MARK: - Тестовые менеджеры

/// Менеджер, который «думает» дольше таймаута.
private actor SlowLookupManager: BackupManagerProtocol {
    private let delay: Duration
    private let result: BackupLookupOutcome

    init(delay: Duration, result: BackupLookupOutcome) {
        self.delay = delay
        self.result = result
    }

    func lookupBackupVersions() async -> BackupLookupOutcome {
        try? await Task.sleep(for: delay)
        return result
    }

    func isAvailable() async -> Bool { true }
    func backupNow() async throws {}
    func backupNow(passphrase: String?) async throws {}
    func saveVersionNow(passphrase: String?) async throws {}
    func exportVersion(recordName: String) async throws -> BackupTransferPayload { throw AppError.backupCorrupted }
    func importVersion(from data: Data) async throws -> BackupVersionInfo { throw AppError.backupCorrupted }
    func inspectBackupFile(_ data: Data) async throws -> BackupInfo { throw AppError.backupCorrupted }
    func restoreFromFile(_ data: Data, passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreLatest() async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreLatest(passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreVersion(recordName: String, passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func listBackupVersions() async -> [BackupVersionInfo] { [] }
    func deleteBackupVersion(recordName: String) async throws {}
    func lastBackupInfo() async -> BackupInfo? { nil }
}

/// Менеджер со сценарием исходов: проверяем, что повтор действительно делает новый запрос.
private actor ScriptedLookupManager: BackupManagerProtocol {
    private var results: [BackupLookupOutcome]
    private(set) var calls = 0

    init(results: [BackupLookupOutcome]) {
        self.results = results
    }

    func lookupBackupVersions() async -> BackupLookupOutcome {
        calls += 1
        guard !results.isEmpty else { return .empty }
        return results.removeFirst()
    }

    func isAvailable() async -> Bool { true }
    func backupNow() async throws {}
    func backupNow(passphrase: String?) async throws {}
    func saveVersionNow(passphrase: String?) async throws {}
    func exportVersion(recordName: String) async throws -> BackupTransferPayload { throw AppError.backupCorrupted }
    func importVersion(from data: Data) async throws -> BackupVersionInfo { throw AppError.backupCorrupted }
    func inspectBackupFile(_ data: Data) async throws -> BackupInfo { throw AppError.backupCorrupted }
    func restoreFromFile(_ data: Data, passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreLatest() async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreLatest(passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func restoreVersion(recordName: String, passphrase: String?) async throws -> RestoreReceipt { throw AppError.backupCorrupted }
    func listBackupVersions() async -> [BackupVersionInfo] { [] }
    func deleteBackupVersion(recordName: String) async throws {}
    func lastBackupInfo() async -> BackupInfo? { nil }
}
