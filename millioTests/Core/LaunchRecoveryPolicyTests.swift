import Foundation
import Testing
@testable import millio

struct LaunchRecoveryPolicyTests {
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

    @Test("Evaluator skips restore on normal relaunch when scoped store already exists")
    func testEvaluateSkipsRestoreForExistingLocalStore() {
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

        #expect(decision == .skip(.existingLocalStore))
        #expect(!decision.shouldPresentRestore)
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

        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )
    }

    @Test("Policy does not enter restore after language change and normal relaunch when local store already exists")
    func testShouldNotPresentRestoreAfterLanguageChangeAndRelaunch() {
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

        #expect(decision == .skip(.existingLocalStore))
        #expect(!decision.shouldPresentRestore)
        #expect(
            !LaunchRecoveryPolicy.shouldPresentRestore(
                lifecycle: .ready,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )
    }
}
