//
//  LaunchRecoveryPolicy.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import Foundation

struct LaunchRecoveryPolicy {
    struct Input {
        let lifecycle: AppLifecycleState
        let hasCompletedOnboarding: Bool
        let didLocalStoreExistBeforeLaunch: Bool
        let localDataCount: Int
        let latestBackupInfo: BackupInfo?
    }

    enum BlockReason: Equatable {
        case onboardingIncomplete
        case lifecycleNotReady
        case existingLocalStore
        case localDataPresent
        case noBackupAvailable
    }

    enum Decision: Equatable {
        case presentRestore
        case skip(BlockReason)

        var shouldPresentRestore: Bool {
            if case .presentRestore = self {
                return true
            }
            return false
        }
    }

    static func evaluate(_ input: Input) -> Decision {
        guard input.hasCompletedOnboarding else {
            return .skip(.onboardingIncomplete)
        }
        guard input.lifecycle == .ready else {
            return .skip(.lifecycleNotReady)
        }
        // Normal relaunch: store existed and still contains user data — nothing to recover.
        // But if the store existed yet is now empty (e.g. SwiftData schema migration wiped it),
        // fall through so we can offer restore from the available backup.
        if input.didLocalStoreExistBeforeLaunch && input.localDataCount > 0 {
            return .skip(.existingLocalStore)
        }
        guard input.localDataCount == 0 else {
            return .skip(.localDataPresent)
        }
        guard input.latestBackupInfo != nil else {
            return .skip(.noBackupAvailable)
        }
        return .presentRestore
    }

    static func shouldPresentRestore(
        lifecycle: AppLifecycleState,
        hasCompletedOnboarding: Bool,
        didLocalStoreExistBeforeLaunch: Bool,
        localDataCount: Int,
        latestBackupInfo: BackupInfo?
    ) -> Bool {
        evaluate(
            Input(
                lifecycle: lifecycle,
                hasCompletedOnboarding: hasCompletedOnboarding,
                didLocalStoreExistBeforeLaunch: didLocalStoreExistBeforeLaunch,
                localDataCount: localDataCount,
                latestBackupInfo: latestBackupInfo
            )
        ).shouldPresentRestore
    }
}
