//
//  StartupCoordinator.swift
//  millio
//
//  Created by Codex on 15.03.2026.
//

import Foundation

@MainActor
final class StartupCoordinator {
    private(set) var activeScope: DataScope

    private var coldStartTask: Task<Void, Never>?
    private var didFinishColdStart = false
    private var scopeSwitchTask: Task<Bool, Never>?
    private var scopeSwitchSequence: UInt = 0

    init(initialScope: DataScope = .guest) {
        self.activeScope = initialScope
    }

    func runColdStartIfNeeded(
        operation: @escaping @MainActor () async -> Void
    ) async {
        if let coldStartTask {
            await coldStartTask.value
            return
        }

        guard !didFinishColdStart else { return }

        let task = Task { @MainActor [weak self] in
            await operation()
            self?.didFinishColdStart = true
            self?.coldStartTask = nil
        }

        coldStartTask = task
        await task.value
    }

    @discardableResult
    func switchScopeIfNeeded(
        to targetScope: DataScope,
        operation: @escaping @MainActor (_ targetScope: DataScope) async -> Bool
    ) async -> Bool {
        guard targetScope != activeScope || scopeSwitchTask != nil else {
            return false
        }

        scopeSwitchSequence += 1
        let sequence = scopeSwitchSequence

        scopeSwitchTask?.cancel()

        let task = Task { @MainActor [weak self] in
            let changed = await operation(targetScope)
            guard let self else { return false }
            guard !Task.isCancelled, sequence == self.scopeSwitchSequence else { return false }

            if changed {
                self.activeScope = targetScope
            }
            self.scopeSwitchTask = nil
            return changed
        }

        scopeSwitchTask = task
        return await task.value
    }
}
