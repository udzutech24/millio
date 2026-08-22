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
        #expect(!LaunchRecoveryPolicy.Decision.skip(.onboardingIncomplete).locksLaunchRecovery)
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

    @Test("Evaluator skips restore when onboarding is incomplete")
    func testEvaluateSkipsRestoreForIncompleteOnboarding() {
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

        #expect(decision == .skip(.onboardingIncomplete))
        #expect(!decision.shouldPresentRestore)
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
}
