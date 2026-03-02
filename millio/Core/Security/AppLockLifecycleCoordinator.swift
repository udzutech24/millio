//
//  AppLockLifecycleCoordinator.swift
//  millio
//
//  Created by Codex on 02.03.2026.
//

import Foundation

@MainActor
struct AppLockLifecycleCoordinator {
    func enforceLockStateOnLaunch(appState: AppState, hasPin: Bool) {
        guard appState.isAppLockEnabled else {
            appState.isAppLocked = false
            return
        }
        guard hasPin else {
            appState.isAppLockEnabled = false
            appState.isBiometricUnlockEnabled = false
            appState.isAppLocked = false
            return
        }
        appState.isAppLocked = true
    }

    func handleWillResignActive(appState: AppState) {
        guard appState.isAppLockEnabled else { return }
        appState.isAppLocked = true
    }

    func handleDidBecomeActive(
        appState: AppState,
        unlockWithBiometrics: @escaping @MainActor () async -> Bool
    ) async {
        guard appState.isAppLockEnabled, appState.isAppLocked else { return }
        _ = await unlockWithBiometrics()
    }
}
