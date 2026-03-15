import Foundation
import Testing
@testable import millio

struct LaunchRecoveryPolicyTests {
    @Test("Policy enters restore only when app is ready, onboarding is complete, local data is empty, and backup exists")
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
}
