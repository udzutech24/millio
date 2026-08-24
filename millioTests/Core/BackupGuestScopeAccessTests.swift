import Foundation
import Testing
@testable import millio

/// R10: облачные копии доступны только в авторизованном scope.
/// Регрессия: гость видел список версий владельца устройства и восстанавливал их в гостевой стор.
struct BackupGuestScopeAccessTests {
    private let userScopeKey = DataScope.user(id: "owner-1").storeConfigurationName
    private let guestScopeKey = DataScope.guest.storeConfigurationName

    @MainActor
    private func makeAppState(scopeKey: String) -> AppState {
        let appState = AppState()
        appState.activeScopeKey = scopeKey
        appState.isBackupEnabled = true
        return appState
    }

    private func makeManager(appState: AppState, spy: SpyBackupManager) -> SwitchingBackupManager {
        SwitchingBackupManager(appState: appState, enabled: spy, disabled: SpyBackupManager(available: false))
    }

    @Test("Guest scope is denied cloud backup access by policy")
    func testPolicyDeniesGuestScope() {
        #expect(BackupAccessPolicy.isCloudAccessAllowed(scopeKey: guestScopeKey) == false)
        #expect(BackupAccessPolicy.isCloudAccessAllowed(scopeKey: userScopeKey))
    }

    @Test("Guest scope gets no backup versions list")
    func testGuestScopeSeesNoVersions() async {
        let appState = await MainActor.run { makeAppState(scopeKey: guestScopeKey) }
        let spy = SpyBackupManager(available: true, versions: [BackupVersionInfoFixtures.pinned])
        let manager = makeManager(appState: appState, spy: spy)

        let versions = await manager.listBackupVersions()
        let outcome = await manager.lookupBackupVersions()
        let lastInfo = await manager.lastBackupInfo()
        let infoCalls = await spy.infoCalls

        #expect(versions.isEmpty)
        #expect(outcome == .failed(.requiresSignIn))
        #expect(lastInfo == nil)
        // Облако не опрашивалось вовсе — отказ до сетевого запроса.
        #expect(infoCalls == 0)
    }

    @Test("Guest scope restore is rejected at service level")
    func testGuestScopeRestoreRejected() async {
        let appState = await MainActor.run { makeAppState(scopeKey: guestScopeKey) }
        let spy = SpyBackupManager(available: true)
        let manager = makeManager(appState: appState, spy: spy)

        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.restoreLatest() }
        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.restoreLatest(passphrase: "p") }
        await #expect(throws: AppError.backupRequiresSignIn) {
            try await manager.restoreVersion(recordName: "v1", passphrase: nil)
        }

        let restoreCalls = await spy.restoreCalls
        #expect(restoreCalls == 0)
    }

    @Test("Guest scope file import and inspection are rejected")
    func testGuestScopeFileImportRejected() async {
        let appState = await MainActor.run { makeAppState(scopeKey: guestScopeKey) }
        let spy = SpyBackupManager(available: true)
        let manager = makeManager(appState: appState, spy: spy)

        await #expect(throws: AppError.backupRequiresSignIn) {
            try await manager.restoreFromFile(Data([0x01]), passphrase: nil)
        }
        await #expect(throws: AppError.backupRequiresSignIn) {
            _ = try await manager.inspectBackupFile(Data([0x01]))
        }
        await #expect(throws: AppError.backupRequiresSignIn) {
            _ = try await manager.importVersion(from: Data([0x01]))
        }

        let restoreCalls = await spy.restoreCalls
        #expect(restoreCalls == 0)
    }

    @Test("Guest scope backup creation, export and deletion are rejected")
    func testGuestScopeWriteOperationsRejected() async {
        let appState = await MainActor.run { makeAppState(scopeKey: guestScopeKey) }
        let spy = SpyBackupManager(available: true)
        let manager = makeManager(appState: appState, spy: spy)

        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.backupNow() }
        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.backupNow(passphrase: nil) }
        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.saveVersionNow(passphrase: nil) }
        await #expect(throws: AppError.backupRequiresSignIn) { try await manager.deleteBackupVersion(recordName: "v1") }
        await #expect(throws: AppError.backupRequiresSignIn) { _ = try await manager.exportVersion(recordName: "v1") }

        let backupCalls = await spy.backupCalls
        #expect(backupCalls == 0)
    }

    @Test("Authenticated scope keeps full backup access")
    func testAuthenticatedScopeKeepsAccess() async throws {
        let appState = await MainActor.run { makeAppState(scopeKey: userScopeKey) }
        let spy = SpyBackupManager(available: true, versions: [BackupVersionInfoFixtures.pinned])
        let manager = makeManager(appState: appState, spy: spy)

        let versions = await manager.listBackupVersions()
        try await manager.saveVersionNow(passphrase: nil)
        try await manager.restoreVersion(recordName: "v1", passphrase: nil)
        _ = try await manager.exportVersion(recordName: "v1")

        let backupCalls = await spy.backupCalls
        let restoreCalls = await spy.restoreCalls

        #expect(versions.count == 1)
        #expect(backupCalls == 1)
        #expect(restoreCalls == 1)
    }

    @Test("Logout during an open backup screen revokes access immediately")
    func testLogoutRevokesAccessWithoutRecreatingManager() async throws {
        let appState = await MainActor.run { makeAppState(scopeKey: userScopeKey) }
        let spy = SpyBackupManager(available: true, versions: [BackupVersionInfoFixtures.pinned])
        let manager = makeManager(appState: appState, spy: spy)

        let versionsBefore = await manager.listBackupVersions()
        #expect(versionsBefore.count == 1)

        // Тот же экземпляр менеджера (экран уже открыт) — меняется только активный scope.
        await MainActor.run { appState.activeScopeKey = DataScope.guest.storeConfigurationName }

        let versionsAfter = await manager.listBackupVersions()
        #expect(versionsAfter.isEmpty)
        await #expect(throws: AppError.backupRequiresSignIn) {
            try await manager.restoreVersion(recordName: "v1", passphrase: nil)
        }
    }

    @Test("Sign-in denial message is localized, not a technical English string")
    func testDenialMessageIsLocalized() {
        let message = RestoreErrorPresenter.userMessage(for: AppError.backupRequiresSignIn)

        #expect(message != AppError.backupRequiresSignIn.localizedDescription)
        #expect(message == BackupLookupFailureReason.requiresSignIn.userMessage)
        #expect(message.isEmpty == false)
    }
}

enum BackupVersionInfoFixtures {
    static let pinned = BackupVersionInfo(
        recordName: "v1",
        date: Date(timeIntervalSince1970: 0),
        size: 1_024,
        version: "1.0",
        isPinned: true
    )
}
