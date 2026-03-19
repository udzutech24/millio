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
        // Recovery should only be offered when the scoped store did not exist before
        // launch. If the file was already present, this is a normal relaunch and we
        // should not nudge the user into replacing existing local state.
        guard !input.didLocalStoreExistBeforeLaunch else {
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
