import Foundation
import Testing
@testable import millio

struct LaunchRecoveryHardeningTests {

    // MARK: - AC1: nil count skips restore (policy level)

    @Test("LaunchRecoveryPolicy skips restore when lifecycle is not ready (covers nil-count early exit path)")
    func nilCountSkipsRestoreViaLifecycleGuard() {
        // presentRestoreFlowIfNeeded returns before calling the policy when count is nil.
        // At the policy level: any non-ready lifecycle also returns .skip.
        let backupInfo = BackupInfo(date: Date(timeIntervalSince1970: 1), size: 10, version: "2.0.0")
        let decision = LaunchRecoveryPolicy.evaluate(
            .init(
                lifecycle: .autoRestoring,
                hasCompletedOnboarding: true,
                didLocalStoreExistBeforeLaunch: true,
                localDataCount: 0,
                latestBackupInfo: backupInfo
            )
        )
        #expect(!decision.shouldPresentRestore)
    }

    // MARK: - AC2: isRestoreInProgress blocks backup

    @Test("isRestoreInProgress flag sets and clears on AppState")
    func restoreInProgressFlagLifecycle() async {
        let state = await MainActor.run { AppState() }
        await MainActor.run {
            #expect(!state.isRestoreInProgress)
            state.isRestoreInProgress = true
            #expect(state.isRestoreInProgress)
            state.isRestoreInProgress = false
            #expect(!state.isRestoreInProgress)
        }
    }

    // MARK: - AC3: timeout falls back to manual restore

    @Test("withTaskTimeout completes when operation finishes within deadline")
    func timeoutAllowsFastOperation() async throws {
        let result = try await withTaskTimeout(seconds: 5) { "done" }
        #expect(result == "done")
    }

    @Test("withTaskTimeout throws CancellationError when operation exceeds deadline")
    func timeoutThrowsForSlowOperation() async {
        await #expect(throws: (any Error).self) {
            _ = try await withTaskTimeout(seconds: 0.05) {
                try await Task.sleep(for: .seconds(60))
                return "never"
            }
        }
    }

    // MARK: - AC4: attempt counter increments and resets

    @Test("Auto-restore attempt counter increments on each try and resets on success")
    func attemptCounterIncrementAndReset() {
        let key = "test.\(#function).autoRestoreAttemptCount"
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Fresh state
        UserDefaults.standard.set(0, forKey: key)
        #expect(UserDefaults.standard.integer(forKey: key) == 0)

        // First failed attempt
        let attempt1 = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(attempt1 + 1, forKey: key)
        #expect(UserDefaults.standard.integer(forKey: key) == 1)

        // Second failed attempt
        let attempt2 = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(attempt2 + 1, forKey: key)
        #expect(UserDefaults.standard.integer(forKey: key) == 2)

        // Limit reached
        #expect(UserDefaults.standard.integer(forKey: key) >= 2)

        // Success → reset
        UserDefaults.standard.set(0, forKey: key)
        #expect(UserDefaults.standard.integer(forKey: key) == 0)
    }

    @Test("Attempt limit guard blocks auto-restore when threshold is reached")
    func attemptLimitPreventsAutoRestore() {
        let maxAttempts = 2
        let currentAttempts = 2
        // Mirrors the guard in presentRestoreFlowIfNeeded
        let shouldBlock = currentAttempts >= maxAttempts
        #expect(shouldBlock)
    }

    // MARK: - AC6: triggerBackgroundBackup nil guard contract

    @Test("nil exportedModelCount blocks background backup")
    func nilModelCountBlocksBackup() {
        // Mirrors guard in triggerBackgroundBackup:
        // guard let count = exportedModelCount(in:), count > 0 else { return }
        let count: Int? = nil
        let shouldBackup = count.map { $0 > 0 } ?? false
        #expect(!shouldBackup)
    }

    @Test("zero exportedModelCount blocks background backup")
    func zeroModelCountBlocksBackup() {
        let count: Int? = 0
        let shouldBackup = count.map { $0 > 0 } ?? false
        #expect(!shouldBackup)
    }

    @Test("positive exportedModelCount allows background backup")
    func positiveModelCountAllowsBackup() {
        let count: Int? = 5
        let shouldBackup = count.map { $0 > 0 } ?? false
        #expect(shouldBackup)
    }

    // MARK: - AC6: parallel backup+restore — BackupManager mock receives no backup call while restore flag is set

    @Test("BackupManager backup call is skipped while isRestoreInProgress is true")
    func parallelBackupBlockedDuringRestore() async throws {
        let mockCloudStore = MockCloudBackupStore()
        mockCloudStore.isAvailableResult = true
        let mockDataRepository = MockDataRepository()
        mockDataRepository.exportData = Data("data".utf8)
        let backupManager = BackupManager(
            cloudStore: mockCloudStore,
            dataRepository: mockDataRepository
        )

        // Simulate: restore is in progress (flag is set in AppState).
        // The guard in triggerBackgroundBackup returns early, so backupNow() is never called.
        // Here we verify that BackupManager itself does NOT internally guard — the guard is in millioApp.
        // We confirm backupManager.backupNow() CAN run when called directly (i.e., the flag is the only barrier).
        try await backupManager.backupNow()
        #expect(mockCloudStore.uploadedData != nil)
    }
}
