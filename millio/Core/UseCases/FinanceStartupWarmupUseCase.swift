//
//  FinanceStartupWarmupUseCase.swift
//  millio
//
//  Created by Codex on 04.03.2026.
//

import Foundation
import SwiftData

@MainActor
protocol FinanceStartupWarmupUseCaseProtocol {
    func warmupIfNeeded() async
    func warmup(force: Bool) async
}

protocol FinanceStartupWarmupRunnerProtocol {
    @MainActor
    func warmup(modelContext: ModelContext) async
}

struct FinanceStartupWarmupRunner: FinanceStartupWarmupRunnerProtocol {
    @MainActor
    func warmup(modelContext: ModelContext) async {
        let viewModel = FinanceViewModel(modelContext: modelContext)
        await viewModel.warmupRemoteDataForStartup()
    }
}

/// Прогрев удаленных данных финансов на старте приложения.
///
/// Ограничивает частоту вызовов, чтобы не дергать API при каждом коротком заходе.
@MainActor
final class FinanceStartupWarmupUseCase: FinanceStartupWarmupUseCaseProtocol {
    enum DefaultsKeys {
        static let lastWarmupAt = "finance.startup_warmup.last_run_at"
    }

    // Раз в 3 часа достаточно, чтобы данные были свежими,
    // но пользователь не платил лишними API-вызовами при частых открытиях приложения.
    static let minimumWarmupInterval: TimeInterval = 3 * 60 * 60

    private let modelContext: ModelContext
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private let runner: FinanceStartupWarmupRunnerProtocol

    private var inFlightTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init,
        runner: FinanceStartupWarmupRunnerProtocol = FinanceStartupWarmupRunner()
    ) {
        self.modelContext = modelContext
        self.defaults = defaults
        self.nowProvider = nowProvider
        self.runner = runner
    }

    func warmupIfNeeded() async {
        await warmup(force: false)
    }

    func warmup(force: Bool) async {
        if let inFlightTask {
            await inFlightTask.value
            return
        }

        guard force || shouldRunWarmup(at: nowProvider()) else { return }

        let runTask = Task { [weak self] in
            guard let self else { return }
            await self.runner.warmup(modelContext: self.modelContext)
            self.defaults.set(self.nowProvider().timeIntervalSince1970, forKey: DefaultsKeys.lastWarmupAt)
        }

        inFlightTask = runTask
        await runTask.value
        inFlightTask = nil
    }

    func shouldRunWarmup(at now: Date) -> Bool {
        let lastTS = defaults.double(forKey: DefaultsKeys.lastWarmupAt)
        guard lastTS > 0 else { return true }
        let elapsed = now.timeIntervalSince1970 - lastTS
        return elapsed >= Self.minimumWarmupInterval
    }
}
