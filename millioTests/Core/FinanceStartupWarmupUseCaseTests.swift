import Foundation
import Testing
import SwiftData
@testable import millio

@MainActor
private final class SpyFinanceStartupWarmupRunner: FinanceStartupWarmupRunnerProtocol {
    private(set) var callCount = 0

    func warmup(modelContext: ModelContext) async {
        callCount += 1
    }
}

@Suite(.serialized)
@MainActor
struct FinanceStartupWarmupUseCaseTests {
    private func makeModelContext() throws -> ModelContext {
        let schema = AppSchema.create()
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return container.mainContext
    }

    private func makeIsolatedDefaults() -> (UserDefaults, String) {
        let suiteName = "FinanceStartupWarmupUseCaseTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (defaults, suiteName)
    }

    @Test("Startup warmup запускается при первом входе и сохраняет timestamp")
    func testWarmupRunsFirstTimeAndStoresTimestamp() async throws {
        let modelContext = try makeModelContext()
        let runner = SpyFinanceStartupWarmupRunner()
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let useCase = FinanceStartupWarmupUseCase(
            modelContext: modelContext,
            defaults: defaults,
            nowProvider: { now },
            runner: runner
        )

        await useCase.warmupIfNeeded()

        #expect(runner.callCount == 1)
        #expect(defaults.double(forKey: FinanceStartupWarmupUseCase.DefaultsKeys.lastWarmupAt) == now.timeIntervalSince1970)
    }

    @Test("Startup warmup не запускается повторно раньше cooldown")
    func testWarmupIsThrottledByMinimumInterval() async throws {
        let modelContext = try makeModelContext()
        let runner = SpyFinanceStartupWarmupRunner()
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let useCase = FinanceStartupWarmupUseCase(
            modelContext: modelContext,
            defaults: defaults,
            nowProvider: { now },
            runner: runner
        )

        await useCase.warmupIfNeeded()
        #expect(runner.callCount == 1)

        now = now.addingTimeInterval(FinanceStartupWarmupUseCase.minimumWarmupInterval - 60)
        await useCase.warmupIfNeeded()

        #expect(runner.callCount == 1)
    }

    @Test("Принудительный warmup игнорирует cooldown")
    func testForcedWarmupBypassesThrottle() async throws {
        let modelContext = try makeModelContext()
        let runner = SpyFinanceStartupWarmupRunner()
        let (defaults, suiteName) = makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var now = Date(timeIntervalSince1970: 1_700_000_000)
        let useCase = FinanceStartupWarmupUseCase(
            modelContext: modelContext,
            defaults: defaults,
            nowProvider: { now },
            runner: runner
        )

        await useCase.warmupIfNeeded()
        #expect(runner.callCount == 1)

        now = now.addingTimeInterval(60)
        await useCase.warmup(force: true)

        #expect(runner.callCount == 2)
    }
}
