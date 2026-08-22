import Testing
@testable import millio

@Suite(.serialized)
@MainActor
struct StartupCoordinatorTests {

    @Test("Кешированная авторизованная сессия пропускает декоративную задержку splash")
    func cachedSessionSkipsMinimumLaunchDuration() {
        #expect(
            ColdStartPresentationPolicy.minimumLaunchDurationOverride(
                hasCachedAuthenticatedSession: true
            ) == 0
        )
        #expect(
            ColdStartPresentationPolicy.minimumLaunchDurationOverride(
                hasCachedAuthenticatedSession: false
            ) == nil
        )
    }
    @Test("Cold start runs only once even if the view task is recreated")
    func coldStartRunsOnlyOnce() async {
        let coordinator = StartupCoordinator(initialScope: .guest)
        var invocationCount = 0

        await coordinator.runColdStartIfNeeded {
            invocationCount += 1
        }

        await coordinator.runColdStartIfNeeded {
            invocationCount += 1
        }

        #expect(invocationCount == 1)
    }

    @Test("Scope switch updates active scope without re-running cold start")
    func scopeSwitchUpdatesActiveScope() async {
        let coordinator = StartupCoordinator(initialScope: .guest)
        var switchedScopes: [DataScope] = []

        let changed = await coordinator.switchScopeIfNeeded(to: .user(id: "42")) { scope in
            switchedScopes.append(scope)
            return true
        }

        #expect(changed == true)
        #expect(switchedScopes == [.user(id: "42")])
        #expect(coordinator.activeScope == .user(id: "42"))
    }

    @Test("Latest scope switch wins and stale task is ignored")
    func latestScopeSwitchWins() async {
        let coordinator = StartupCoordinator(initialScope: .guest)
        var appliedScopes: [DataScope] = []

        let firstTask = Task { @MainActor in
            await coordinator.switchScopeIfNeeded(to: .user(id: "first")) { scope in
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard !Task.isCancelled else { return false }
                appliedScopes.append(scope)
                return true
            }
        }

        try? await Task.sleep(nanoseconds: 5_000_000)

        let secondChanged = await coordinator.switchScopeIfNeeded(to: .user(id: "second")) { scope in
            appliedScopes.append(scope)
            return true
        }

        let firstChanged = await firstTask.value

        #expect(secondChanged == true)
        #expect(firstChanged == false)
        #expect(appliedScopes == [.user(id: "second")])
        #expect(coordinator.activeScope == .user(id: "second"))
    }
}
