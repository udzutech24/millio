//
//  LaunchRecoveryGate.swift
//  millio
//

import Foundation

/// Единственный владелец состояния launch-recovery в пределах запуска процесса:
/// гасит повторные автоматические запуски восстановления для одного и того же поколения scope
/// и отсекает stale-колбэки, оставшиеся от предыдущего аккаунта.
///
/// Живёт вне `@State` любой вью (держится App-level `@State`), поэтому переживает
/// пересоздание дерева по `RootSceneIdentity` — без этого повторный вызов
/// `presentRestoreFlowIfNeeded` открывал RestoreView второй раз и обнулял его состояние.
@MainActor
final class LaunchRecoveryGate {

    /// Пропуск на одну попытку recovery. Действителен, пока не сменилось поколение scope.
    struct Token: Equatable {
        let scopeKey: String
        let generation: UInt
    }

    /// Чем закончилась попытка. `.unresolved` (сбой лукапа, ещё не готовый lifecycle)
    /// НЕ считается принятым решением — иначе строгая идемпотентность навсегда убила бы recovery (SR7).
    enum Outcome: Equatable {
        case decided
        case unresolved
    }

    private enum Phase {
        case evaluating
        case decided
    }

    private struct Entry {
        let generation: UInt
        var phase: Phase
    }

    private(set) var generation: UInt = 0
    private var entries: [String: Entry] = [:]

    /// Вызывается при свопе контейнера/аккаунта. Все ранее выданные токены становятся stale.
    func bumpGeneration() {
        generation &+= 1
        entries.removeAll()
    }

    /// Возвращает токен, если для текущего поколения scope решение ещё не принималось.
    /// `nil` = повторный вызов, должен быть no-op.
    func beginEvaluation(scopeKey: String) -> Token? {
        if let entry = entries[scopeKey], entry.generation == generation {
            return nil
        }
        entries[scopeKey] = Entry(generation: generation, phase: .evaluating)
        return Token(scopeKey: scopeKey, generation: generation)
    }

    /// Фиксирует исход попытки. Устаревший токен игнорируется.
    func finish(_ token: Token, outcome: Outcome) {
        guard isCurrent(token) else { return }
        switch outcome {
        case .decided:
            entries[token.scopeKey] = Entry(generation: generation, phase: .decided)
        case .unresolved:
            entries[token.scopeKey] = nil
        }
    }

    /// Токен всё ещё принадлежит активному поколению scope.
    func isCurrent(_ token: Token) -> Bool {
        token.generation == generation && entries[token.scopeKey]?.generation == generation
    }

    /// Публиковать результат восстановления (lifecycle, счётчики, данные) можно только
    /// пока поколение scope не сменилось: logout/смена аккаунта в середине restore
    /// не должны опубликовать успех в чужой scope.
    func shouldPublishRestoreOutcome(for token: Token) -> Bool {
        isCurrent(token)
    }
}
