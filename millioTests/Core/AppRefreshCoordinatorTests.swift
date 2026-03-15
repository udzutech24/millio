import Foundation
import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct AppRefreshCoordinatorTests {
    @Test("Subscription refresh is coalesced across startup and foreground")
    func subscriptionRefreshIsCoalesced() async {
        let appState = AppState()
        let subscriptionManager = StubSubscriptionRefresh()
        let coordinator = AppRefreshCoordinator(
            now: fixedNowClock(),
            subscriptionCooldown: 5,
            authCooldown: 30
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .coldStart,
            appState: appState,
            subscriptionManager: subscriptionManager
        )
        await coordinator.refreshSubscriptionIfNeeded(
            reason: .appDidBecomeActive,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        #expect(subscriptionManager.refreshCalls == 1)
        #expect(appState.subscriptionAccessSource == .trial)
    }

    @Test("Auth user refresh is coalesced across repeated profile tasks")
    func authRefreshIsCoalesced() async {
        let authManager = StubAuthUserRefresh()
        let coordinator = AppRefreshCoordinator(
            now: fixedNowClock(),
            subscriptionCooldown: 5,
            authCooldown: 30
        )

        await coordinator.refreshAuthenticatedUserIfNeeded(
            reason: .profileAppeared,
            authManager: authManager
        )
        await coordinator.refreshAuthenticatedUserIfNeeded(
            reason: .profileAppeared,
            authManager: authManager
        )

        #expect(authManager.reloadCalls == 1)
    }

    @Test("Forced subscription refresh bypasses cooldown")
    func forcedSubscriptionRefreshBypassesCooldown() async {
        let appState = AppState()
        let subscriptionManager = StubSubscriptionRefresh()
        let coordinator = AppRefreshCoordinator(
            now: fixedNowClock(),
            subscriptionCooldown: 5,
            authCooldown: 30
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .coldStart,
            appState: appState,
            subscriptionManager: subscriptionManager
        )
        await coordinator.refreshSubscriptionIfNeeded(
            reason: .profileAppeared,
            appState: appState,
            subscriptionManager: subscriptionManager,
            force: true
        )

        #expect(subscriptionManager.refreshCalls == 2)
    }

    @Test("Foreground subscription refresh is skipped while cold start refresh is still running")
    func foregroundRefreshWaitsForColdStartPolicy() async {
        let appState = AppState()
        let subscriptionManager = SlowSubscriptionRefresh()
        let coordinator = AppRefreshCoordinator(
            now: advancingNowClock(),
            subscriptionCooldown: 5,
            authCooldown: 30
        )

        let coldStartTask = Task {
            await coordinator.refreshSubscriptionIfNeeded(
                reason: .coldStart,
                appState: appState,
                subscriptionManager: subscriptionManager
            )
        }

        try? await Task.sleep(nanoseconds: 5_000_000)

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .appDidBecomeActive,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        await coldStartTask.value

        #expect(subscriptionManager.refreshCalls == 1)
    }

    @Test("Foreground subscription refresh is skipped before first startup refresh even begins")
    func foregroundRefreshIsSkippedBeforeInitialStartupRefresh() async {
        let appState = AppState()
        let subscriptionManager = StubSubscriptionRefresh()
        let coordinator = AppRefreshCoordinator(
            now: fixedNowClock(),
            subscriptionCooldown: 5,
            authCooldown: 30
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .appDidBecomeActive,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .coldStart,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        #expect(subscriptionManager.refreshCalls == 1)
    }

    @Test("First foreground subscription refresh after startup is skipped")
    func firstForegroundRefreshAfterStartupIsSkipped() async {
        let appState = AppState()
        let subscriptionManager = StubSubscriptionRefresh()
        let coordinator = AppRefreshCoordinator(
            now: advancingNowClock(),
            subscriptionCooldown: 0,
            authCooldown: 30
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .coldStart,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .appDidBecomeActive,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        await coordinator.refreshSubscriptionIfNeeded(
            reason: .appDidBecomeActive,
            appState: appState,
            subscriptionManager: subscriptionManager
        )

        #expect(subscriptionManager.refreshCalls == 2)
    }

    private func fixedNowClock() -> () -> Date {
        let now = Date(timeIntervalSince1970: 1_000)
        return { now }
    }

    private func advancingNowClock() -> () -> Date {
        let start = Date(timeIntervalSince1970: 1_000)
        var tick: TimeInterval = 0
        return {
            defer { tick += 6 }
            return start.addingTimeInterval(tick)
        }
    }
}

@MainActor
private final class StubSubscriptionRefresh: SubscriptionRefreshing {
    var refreshCalls = 0
    var snapshot = SubscriptionSnapshot(
        status: .trial,
        expirationDate: nil,
        isTrialActive: true,
        hasDebugPremiumOverride: false,
        hasTrialDisabledOverride: false
    )

    func checkSubscriptionStatus(force: Bool) async {
        refreshCalls += 1
    }
}

@MainActor
private final class StubAuthUserRefresh: AuthUserRefreshing {
    var isAuthenticated = true
    var reloadCalls = 0

    func reloadCurrentUser() async {
        reloadCalls += 1
    }
}

@MainActor
private final class SlowSubscriptionRefresh: SubscriptionRefreshing {
    var refreshCalls = 0
    var snapshot = SubscriptionSnapshot(
        status: .trial,
        expirationDate: nil,
        isTrialActive: true,
        hasDebugPremiumOverride: false,
        hasTrialDisabledOverride: false
    )

    func checkSubscriptionStatus(force: Bool) async {
        refreshCalls += 1
        try? await Task.sleep(nanoseconds: 30_000_000)
    }
}
