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
        let isAuthenticatedUserScope: Bool
        let didLocalStoreExistBeforeLaunch: Bool
        let localDataCount: Int
        let latestBackupInfo: BackupInfo?
        let hasAcknowledgedEmptyRecovery: Bool

        init(
            lifecycle: AppLifecycleState,
            hasCompletedOnboarding: Bool,
            isAuthenticatedUserScope: Bool = true,
            didLocalStoreExistBeforeLaunch: Bool,
            localDataCount: Int,
            latestBackupInfo: BackupInfo?,
            hasAcknowledgedEmptyRecovery: Bool = true
        ) {
            self.lifecycle = lifecycle
            self.hasCompletedOnboarding = hasCompletedOnboarding
            self.isAuthenticatedUserScope = isAuthenticatedUserScope
            self.didLocalStoreExistBeforeLaunch = didLocalStoreExistBeforeLaunch
            self.localDataCount = localDataCount
            self.latestBackupInfo = latestBackupInfo
            self.hasAcknowledgedEmptyRecovery = hasAcknowledgedEmptyRecovery
        }
    }

    enum BlockReason: Equatable {
        case unauthenticatedScope
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
        guard input.isAuthenticatedUserScope else {
            return .skip(.unauthenticatedScope)
        }
        guard input.lifecycle == .ready || input.lifecycle == .onboarding else {
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
        // CloudKit may still be resolving immediately after installation. Do not silently
        // route an empty authenticated store to Dashboard merely because the first lookup
        // returned no metadata. The recovery screen owns retry and explicit continuation.
        if !input.hasAcknowledgedEmptyRecovery {
            return .presentRestore
        }
        guard input.latestBackupInfo != nil else {
            return .skip(.noBackupAvailable)
        }
        return .presentRestore
    }

    static func shouldPresentRestore(
        lifecycle: AppLifecycleState,
        hasCompletedOnboarding: Bool,
        isAuthenticatedUserScope: Bool = true,
        didLocalStoreExistBeforeLaunch: Bool,
        localDataCount: Int,
        latestBackupInfo: BackupInfo?
    ) -> Bool {
        evaluate(
            Input(
                lifecycle: lifecycle,
                hasCompletedOnboarding: hasCompletedOnboarding,
                isAuthenticatedUserScope: isAuthenticatedUserScope,
                didLocalStoreExistBeforeLaunch: didLocalStoreExistBeforeLaunch,
                localDataCount: localDataCount,
                latestBackupInfo: latestBackupInfo
            )
        ).shouldPresentRestore
    }
}
