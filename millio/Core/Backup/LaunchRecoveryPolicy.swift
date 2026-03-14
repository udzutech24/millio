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
        localDataCount: Int,
        latestBackupInfo: BackupInfo?
    ) -> Bool {
        guard hasCompletedOnboarding else { return false }
        guard lifecycle == .ready else { return false }
        guard localDataCount == 0 else { return false }
        return latestBackupInfo != nil
    }
}
