//
//  LaunchRecoveryPolicy.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct LaunchRecoveryPolicy {
    static func shouldPresentRestore(
        lifecycle: AppLifecycleState,
        hasCompletedOnboarding: Bool,
        didLocalStoreExistBeforeLaunch: Bool,
        localDataCount: Int,
        latestBackupInfo: BackupInfo?
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard lifecycle == .ready else { return false }
        // Recovery on launch is only safe for a genuinely new/empty local store.
        // Existing stores may temporarily look empty because of scope routing or export issues,
        // and forcing restore in that case kicks established users out of the app.
        guard didLocalStoreExistBeforeLaunch == false else { return false }
        guard localDataCount == 0 else { return false }
        return latestBackupInfo != nil
    }
}
