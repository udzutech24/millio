import Foundation
import Testing
@testable import millio

/// S11: отказ «продолжить без данных» переживает перезапуск и не протекает между аккаунтами.
struct LaunchRecoveryStateStoreTests {

    private func makeDefaults() throws -> UserDefaults {
        let suite = "test.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    @Test("S11: отказ сохраняется для scope и виден следующему запуску")
    func declineSurvivesRelaunch() throws {
        let defaults = try makeDefaults()
        let scope = DataScope.user(id: "user-a").storeConfigurationName

        #expect(!LaunchRecoveryStateStore(defaults: defaults).hasDeclinedRecovery(scopeKey: scope))
        LaunchRecoveryStateStore(defaults: defaults).recordRecoveryDecline(scopeKey: scope)

        // Новый экземпляр = новый запуск процесса: состояние читается из UserDefaults, не из памяти.
        #expect(LaunchRecoveryStateStore(defaults: defaults).hasDeclinedRecovery(scopeKey: scope))
    }

    @Test("S11: отказ одного аккаунта не наследуется другим (S16)")
    func declineIsPerScope() throws {
        let defaults = try makeDefaults()
        let store = LaunchRecoveryStateStore(defaults: defaults)
        let scopeA = DataScope.user(id: "user-a").storeConfigurationName
        let scopeB = DataScope.user(id: "user-b").storeConfigurationName

        store.recordRecoveryDecline(scopeKey: scopeA)

        #expect(store.hasDeclinedRecovery(scopeKey: scopeA))
        #expect(!store.hasDeclinedRecovery(scopeKey: scopeB), "Смена аккаунта не наследует чужой отказ")
        #expect(!store.hasDeclinedRecovery(scopeKey: DataScope.guest.storeConfigurationName))
    }

    @Test("S11: появление данных в scope снимает прошлый отказ")
    func declineClearedWhenDataAppears() throws {
        let defaults = try makeDefaults()
        let store = LaunchRecoveryStateStore(defaults: defaults)
        let scope = DataScope.user(id: "user-a").storeConfigurationName

        store.recordRecoveryDecline(scopeKey: scope)
        store.clearRecoveryDecline(scopeKey: scope)

        #expect(!store.hasDeclinedRecovery(scopeKey: scope))
    }

    @Test("S11: ручное восстановление после отказа доступно — флаг гасит только авто-путь")
    func manualRestoreRemainsAvailableAfterDecline() throws {
        let defaults = try makeDefaults()
        let store = LaunchRecoveryStateStore(defaults: defaults)
        let scope = DataScope.user(id: "user-a").storeConfigurationName
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")
        store.recordRecoveryDecline(scopeKey: scope)

        // Автоматический путь (единственный потребитель флага) закрыт...
        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                hasDeclinedRecovery: store.hasDeclinedRecovery(scopeKey: scope)
            )
        )
        // ...а ручной restore из Профиля флаг не читает вовсе: после успеха он снимается,
        // и обычная логика запуска снова работает.
        store.clearRecoveryDecline(scopeKey: scope)
        #expect(
            LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                hasDeclinedRecovery: store.hasDeclinedRecovery(scopeKey: scope)
            )
        )
    }

    @Test("S11: отказ не трогает счётчик попыток авто-restore")
    func declineDoesNotAffectAttemptCounter() throws {
        let defaults = try makeDefaults()
        let store = LaunchRecoveryStateStore(defaults: defaults)

        store.registerAutoRestoreAttempt()
        store.recordRecoveryDecline(scopeKey: DataScope.user(id: "user-a").storeConfigurationName)

        #expect(store.autoRestoreAttempts == 1)
    }
}
