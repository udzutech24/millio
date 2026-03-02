import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct AppLockLifecycleCoordinatorTests {
    @Test("Background переход включает lock и запускает biometric unlock при возвращении")
    func testBackgroundToActiveLocksAndTriesBiometricUnlock() async {
        let coordinator = AppLockLifecycleCoordinator()
        let appState = AppState()
        appState.isAppLockEnabled = true
        appState.isBiometricUnlockEnabled = true
        appState.isAppLocked = false

        coordinator.handleWillResignActive(appState: appState)
        #expect(appState.isAppLocked == true)

        var unlockCalls = 0
        await coordinator.handleDidBecomeActive(appState: appState) {
            unlockCalls += 1
            appState.isAppLocked = false
            return true
        }

        #expect(unlockCalls == 1)
        #expect(appState.isAppLocked == false)
    }

    @Test("DidBecomeActive ничего не делает когда app lock выключен")
    func testDidBecomeActiveDoesNothingWhenLockDisabled() async {
        let coordinator = AppLockLifecycleCoordinator()
        let appState = AppState()
        appState.isAppLockEnabled = false
        appState.isAppLocked = false

        var unlockCalls = 0
        await coordinator.handleDidBecomeActive(appState: appState) {
            unlockCalls += 1
            return true
        }

        #expect(unlockCalls == 0)
        #expect(appState.isAppLocked == false)
    }

    @Test("DidBecomeActive не триггерит unlock если приложение уже разблокировано")
    func testDidBecomeActiveDoesNotRelockWhenAlreadyUnlocked() async {
        let coordinator = AppLockLifecycleCoordinator()
        let appState = AppState()
        appState.isAppLockEnabled = true
        appState.isBiometricUnlockEnabled = true
        appState.isAppLocked = false

        var unlockCalls = 0
        await coordinator.handleDidBecomeActive(appState: appState) {
            unlockCalls += 1
            return true
        }

        #expect(unlockCalls == 0)
        #expect(appState.isAppLocked == false)
    }

    @Test("Launch отключает app lock если PIN отсутствует")
    func testLaunchDisablesLockWhenPinMissing() {
        let coordinator = AppLockLifecycleCoordinator()
        let appState = AppState()
        appState.isAppLockEnabled = true
        appState.isBiometricUnlockEnabled = true
        appState.isAppLocked = true

        coordinator.enforceLockStateOnLaunch(appState: appState, hasPin: false)

        #expect(appState.isAppLockEnabled == false)
        #expect(appState.isBiometricUnlockEnabled == false)
        #expect(appState.isAppLocked == false)
    }
}
