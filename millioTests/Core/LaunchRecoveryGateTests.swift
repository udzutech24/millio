import Foundation
import Testing
@testable import millio

/// D1: идемпотентность launch-recovery + SR2/S16 (смена аккаунта в середине restore).
@MainActor
struct LaunchRecoveryGateTests {

    // MARK: - Идемпотентность (D1)

    @Test("Повторный вызов для того же поколения scope — no-op")
    func secondEvaluationInSameGenerationIsNoOp() {
        let gate = LaunchRecoveryGate()
        let first = gate.beginEvaluation(scopeKey: "user_1")
        #expect(first != nil)
        #expect(gate.beginEvaluation(scopeKey: "user_1") == nil)
    }

    @Test("Принятое решение переживает попытки повторной оценки (remount дерева)")
    func decidedStateSurvivesRepeatedCalls() {
        let gate = LaunchRecoveryGate()
        guard let token = gate.beginEvaluation(scopeKey: "user_1") else {
            Issue.record("Первый вызов обязан выдать токен")
            return
        }
        gate.finish(token, outcome: .decided)
        #expect(gate.beginEvaluation(scopeKey: "user_1") == nil)
        #expect(gate.beginEvaluation(scopeKey: "user_1") == nil)
    }

    @Test("Разные scope оцениваются независимо")
    func differentScopesAreIndependent() {
        let gate = LaunchRecoveryGate()
        _ = gate.beginEvaluation(scopeKey: "guest")
        #expect(gate.beginEvaluation(scopeKey: "user_1") != nil)
    }

    // MARK: - SR7: строгая идемпотентность не должна убивать recovery

    @Test("Нерешённый исход (сбой лукапа) допускает повторную попытку")
    func unresolvedOutcomeAllowsRetry() {
        let gate = LaunchRecoveryGate()
        guard let token = gate.beginEvaluation(scopeKey: "user_1") else {
            Issue.record("Первый вызов обязан выдать токен")
            return
        }
        gate.finish(token, outcome: .unresolved)
        #expect(gate.beginEvaluation(scopeKey: "user_1") != nil)
    }

    @Test("Смена поколения scope открывает recovery заново")
    func generationBumpReopensRecovery() {
        let gate = LaunchRecoveryGate()
        guard let token = gate.beginEvaluation(scopeKey: "user_1") else {
            Issue.record("Первый вызов обязан выдать токен")
            return
        }
        gate.finish(token, outcome: .decided)
        gate.bumpGeneration()
        #expect(gate.beginEvaluation(scopeKey: "user_1") != nil)
    }

    // MARK: - S16 (блокирующий): смена аккаунта в середине restore

    @Test("После смены аккаунта stale-токен перестаёт быть текущим")
    func staleTokenIsNotCurrentAfterAccountSwitch() {
        let gate = LaunchRecoveryGate()
        guard let tokenA = gate.beginEvaluation(scopeKey: "user_A") else {
            Issue.record("Токен для user_A не выдан")
            return
        }
        #expect(gate.isCurrent(tokenA))

        gate.bumpGeneration() // logout / вход другим аккаунтом

        #expect(!gate.isCurrent(tokenA))
        #expect(!gate.shouldPublishRestoreOutcome(for: tokenA))
    }

    @Test("Stale-колбэк не публикует успех восстановления в чужой scope")
    func staleCallbackDoesNotPublishSuccess() {
        let gate = LaunchRecoveryGate()
        let appState = AppState()
        appState.lifecycle = .autoRestoring
        appState.isRestoreInProgress = true

        guard let tokenA = gate.beginEvaluation(scopeKey: "user_A") else {
            Issue.record("Токен для user_A не выдан")
            return
        }

        // Пользователь вышел и вошёл другим аккаунтом, пока restore шёл.
        gate.bumpGeneration()
        guard let tokenB = gate.beginEvaluation(scopeKey: "user_B") else {
            Issue.record("Токен для user_B не выдан")
            return
        }
        appState.lifecycle = .ready

        // Колбэк восстановления аккаунта A завершился уже после свопа.
        publishIfAllowed(gate: gate, token: tokenA, lifecycle: .restoring, appState: appState)

        #expect(appState.lifecycle == .ready, "Устаревший restore аккаунта A не должен менять состояние аккаунта B")
        #expect(gate.shouldPublishRestoreOutcome(for: tokenB))
    }

    @Test("Новое поколение не наследует решение предыдущего аккаунта")
    func newAccountGetsOwnDecision() {
        let gate = LaunchRecoveryGate()
        guard let tokenA = gate.beginEvaluation(scopeKey: "user_A") else {
            Issue.record("Токен для user_A не выдан")
            return
        }
        gate.finish(tokenA, outcome: .decided)

        gate.bumpGeneration()
        let tokenB = gate.beginEvaluation(scopeKey: "user_B")
        #expect(tokenB != nil, "Для второго аккаунта recovery обязан оцениваться заново")

        // И stale-финиш аккаунта A не портит состояние аккаунта B.
        gate.finish(tokenA, outcome: .unresolved)
        #expect(gate.beginEvaluation(scopeKey: "user_B") == nil)
    }

    /// Повторяет контракт `millioApp.publishAutoRestoreLifecycle`: публикация только через гейт.
    private func publishIfAllowed(
        gate: LaunchRecoveryGate,
        token: LaunchRecoveryGate.Token,
        lifecycle: AppLifecycleState,
        appState: AppState
    ) {
        guard gate.shouldPublishRestoreOutcome(for: token) else { return }
        appState.lifecycle = lifecycle
    }
}
