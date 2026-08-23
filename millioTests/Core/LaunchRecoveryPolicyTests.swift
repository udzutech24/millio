import Foundation
import Testing
@testable import millio

struct LaunchRecoveryPolicyTests {

    // MARK: - D8: неизвестный счётчик локальных моделей

    @Test("Неизвестный localDataCount не пропускает recovery молча — ручной сценарий")
    func testUnknownCountPresentsManualRestore() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: nil,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .presentRestoreManualOnly(.localDataCountUnknown))
        #expect(decision.shouldPresentRestore)
        #expect(!decision.allowsAutomaticRestore, "Деструктивный авто-restore при неизвестном счётчике запрещён")
        #expect(decision.locksLaunchRecovery)
    }

    @Test("Неизвестный localDataCount без бэкапа — обычный skip")
    func testUnknownCountWithoutBackupSkips() {
        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: nil,
                latestBackupInfo: nil
            )
        )

        #expect(decision == .skip(.noBackupAvailable))
        #expect(!decision.shouldPresentRestore)
    }

    // MARK: - SR7: какие исходы фиксируют решение

    @Test("Транзиентные причины skip не блокируют повторную попытку recovery")
    func testTransientSkipsDoNotLockRecovery() {
        #expect(!LaunchRecoveryPolicy.Decision.skip(.lifecycleNotReady).locksLaunchRecovery)
        #expect(!LaunchRecoveryPolicy.Decision.skip(.noBackupAvailable).locksLaunchRecovery)
        #expect(LaunchRecoveryPolicy.Decision.skip(.localDataPresent).locksLaunchRecovery)
        #expect(LaunchRecoveryPolicy.Decision.skip(.existingLocalStore).locksLaunchRecovery)
        #expect(LaunchRecoveryPolicy.Decision.presentRestore.locksLaunchRecovery)
    }

    @Test("Авто-restore разрешён только для обычного presentRestore")
    func testAutomaticRestoreAllowance() {
        #expect(LaunchRecoveryPolicy.Decision.presentRestore.allowsAutomaticRestore)
        #expect(!LaunchRecoveryPolicy.Decision.presentRestoreManualOnly(.localDataCountUnknown).allowsAutomaticRestore)
        #expect(!LaunchRecoveryPolicy.Decision.skip(.localDataPresent).allowsAutomaticRestore)
    }

    @Test("Evaluator classifies fresh install with backup as launch-time recovery")
    func testEvaluateFreshInstallWithBackup() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .presentRestore)
        #expect(decision.shouldPresentRestore)
    }

    // MARK: - S1: восстановление предлагается ДО онбординга

    @Test("S1: свежая установка с бэкапом предлагает recovery до онбординга")
    func testFreshInstallOffersRecoveryBeforeOnboarding() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .onboarding,
                hasCompletedOnboarding: false,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .presentRestore)
        #expect(decision.shouldPresentRestore)
    }

    @Test("S1: без бэкапа новый пользователь идёт в онбординг, а не в recovery")
    func testFreshInstallWithoutBackupKeepsOnboarding() {
        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .onboarding,
                hasCompletedOnboarding: false,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: nil
            )
        )

        #expect(decision == .skip(.noBackupAvailable))
        #expect(!decision.shouldPresentRestore)
    }

    @Test("S1: гостевой scope не получает recovery даже до онбординга")
    func testGuestScopeBeforeOnboardingStillSkips() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .onboarding,
                hasCompletedOnboarding: false,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                isGuestScope: true
            )
        )

        #expect(decision == .skip(.guestScopeBeforeSignIn))
    }

    @Test("S1: непройденный онбординг + lifecycle .ready — не наш момент, решение откладывается")
    func testIncompleteOnboardingWithReadyLifecycleIsTransient() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: false,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.lifecycleNotReady))
        #expect(!decision.locksLaunchRecovery)
    }

    @Test("S1: пройденный онбординг + lifecycle .onboarding не показывает recovery")
    func testCompletedOnboardingWithOnboardingLifecycleSkips() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .onboarding,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.lifecycleNotReady))
    }

    @Test("S1: выход из экрана восстановления — восстановился в .ready, отказался в онбординг")
    func testLifecycleAfterRestoreFlow() {
        #expect(LaunchRecoveryPolicy.lifecycleAfterRestoreFlow(didRestore: true, hasCompletedOnboarding: false) == .ready)
        #expect(LaunchRecoveryPolicy.lifecycleAfterRestoreFlow(didRestore: true, hasCompletedOnboarding: true) == .ready)
        #expect(
            LaunchRecoveryPolicy.lifecycleAfterRestoreFlow(didRestore: false, hasCompletedOnboarding: false) == .onboarding,
            "Отказ нового пользователя не должен съедать онбординг"
        )
        #expect(LaunchRecoveryPolicy.lifecycleAfterRestoreFlow(didRestore: false, hasCompletedOnboarding: true) == .ready)
    }

    @Test("Evaluator skips restore while app lifecycle is not ready")
    func testEvaluateSkipsRestoreWhenLifecycleIsNotReady() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .launching,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.lifecycleNotReady))
        #expect(!decision.shouldPresentRestore)
    }

    @Test("Evaluator skips restore on normal relaunch when scoped store exists and has data")
    func testEvaluateSkipsRestoreForExistingLocalStoreWithData() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 17_000, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 42,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.existingLocalStore))
        #expect(!decision.shouldPresentRestore)
    }

    @Test("Evaluator offers restore when store existed but data was wiped (schema migration / update)")
    func testEvaluatePresentRestoreWhenStoreExistedButDataWiped() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 17_000, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .presentRestore)
        #expect(decision.shouldPresentRestore)
    }

    @Test("Evaluator skips restore when local SwiftData models are already present")
    func testEvaluateSkipsRestoreForExistingLocalModels() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 3,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.localDataPresent))
        #expect(!decision.shouldPresentRestore)
    }

    @Test("Evaluator skips restore when no backup exists")
    func testEvaluateSkipsRestoreWithoutBackup() {
        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: nil
            )
        )

        #expect(decision == .skip(.noBackupAvailable))
        #expect(!decision.shouldPresentRestore)
    }

    @Test("Policy enters restore only when there is no pre-existing local store, local data is empty, and backup exists")
    func testShouldPresentRestoreOnlyForRecoveryCase() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")

        #expect(
            LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .launching,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: false,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )

        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 3,
                latestBackupInfo: backupInfo
            )
        )

        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: nil
            )
        )

        // Store existed with data → normal relaunch → no restore
        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 5,
                latestBackupInfo: backupInfo
            )
        )

        // Store existed but data wiped (schema migration) → offer restore
        #expect(
            LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )
    }

    @Test("Policy skips restore on normal relaunch when store exists with data (user just relaunched)")
    func testShouldNotPresentRestoreOnNormalRelaunchWithData() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 17_000, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 42,
                latestBackupInfo: backupInfo
            )
        )

        #expect(decision == .skip(.existingLocalStore))
        #expect(!decision.shouldPresentRestore)
    }

    // MARK: - Guest scope (R4 / S10)

    @Test("Гостевой scope до логина: восстановление не предлагается, причина названа явно")
    func testGuestScopeSkipsRecoveryWithExplicitReason() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 17_000, version: "2.0.0")

        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                isGuestScope: true
            )
        )

        #expect(decision == .skip(.guestScopeBeforeSignIn))
        #expect(!decision.shouldPresentRestore)
        #expect(!decision.allowsAutomaticRestore)
    }

    @Test("Отказ по гостевому scope транзиентный: после входа recovery оценивается заново")
    func testGuestScopeSkipDoesNotLockRecovery() {
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 17_000, version: "2.0.0")

        let guestDecision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                isGuestScope: true
            )
        )
        let userDecision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: false,
                localDataCount: 0,
                latestBackupInfo: backupInfo,
                isGuestScope: false
            )
        )

        #expect(!guestDecision.locksLaunchRecovery)
        #expect(userDecision == .presentRestore)
    }
}
