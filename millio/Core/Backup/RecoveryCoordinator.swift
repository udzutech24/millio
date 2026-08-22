import Foundation

@Observable
@MainActor
final class RecoveryCoordinator {
    private(set) var state: RecoveryCoordinatorState = .idle

    private let backupManager: BackupManagerProtocol
    private let localModelCount: () -> Int?
    private let isScopeCurrent: (RecoveryScopeToken) -> Bool
    private let timeoutSeconds: TimeInterval
    private var task: Task<Void, Never>?
    private var operationGeneration: UInt = 0
    private var activeScope: RecoveryScopeToken?

    init(
        backupManager: BackupManagerProtocol,
        localModelCount: @escaping () -> Int?,
        isScopeCurrent: @escaping (RecoveryScopeToken) -> Bool,
        timeoutSeconds: TimeInterval = 45
    ) {
        self.backupManager = backupManager
        self.localModelCount = localModelCount
        self.isScopeCurrent = isScopeCurrent
        self.timeoutSeconds = max(1, timeoutSeconds)
    }

    func discover(scope: RecoveryScopeToken) async {
        cancelActiveOperation(publishCancellation: false)
        activeScope = scope
        guard scope.kind == .authenticated else {
            state = .failed(.invalidScope)
            return
        }
        guard isScopeCurrent(scope) else {
            state = .failed(.scopeChanged)
            return
        }
        guard let count = localModelCount() else {
            state = .failed(.localCountUnavailable)
            return
        }
        guard count == 0 else {
            state = .failed(.localDataPresent(count: count))
            return
        }

        state = .searching
        let versions = await backupManager.listBackupVersions()
        guard isScopeCurrent(scope) else {
            state = .failed(.scopeChanged)
            return
        }
        guard let candidate = versions.first else {
            state = .failed(.noBackup)
            return
        }
        state = .awaitingConfirmation(candidate)
    }

    func restoreConfirmed(recordName: String, passphrase: String?) {
        guard let scope = activeScope, isScopeCurrent(scope) else {
            state = .failed(.scopeChanged)
            return
        }
        cancelActiveOperation(publishCancellation: false)
        operationGeneration &+= 1
        let generation = operationGeneration
        state = .running(.downloading)
        let weakBox = WeakRecoveryCoordinatorBox(self)

        task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let receipt = try await withTaskTimeout(seconds: timeoutSeconds) {
                    try await self.backupManager.restoreVersionVerified(
                        recordName: recordName,
                        passphrase: passphrase,
                        progress: { stage in
                            await MainActor.run {
                                guard let self = weakBox.value,
                                      self.operationGeneration == generation,
                                      self.isScopeCurrent(scope) else { return }
                                self.state = .running(stage)
                            }
                        }
                    )
                }
                guard operationGeneration == generation, isScopeCurrent(scope) else {
                    state = .failed(.scopeChanged)
                    return
                }
                state = .succeeded(receipt)
            } catch is CancellationError {
                guard operationGeneration == generation else { return }
                state = .cancelled
            } catch let failure as RecoveryFailure {
                guard operationGeneration == generation else { return }
                state = .failed(failure)
            } catch {
                guard operationGeneration == generation else { return }
                state = .failed(.underlying(message: Self.safeReasonCode(for: error)))
            }
            task = nil
        }
    }

    /// Runs an explicitly selected restore through the same timeout, scope and
    /// verification boundary used by launch recovery.
    func restoreExplicit(
        recordName: String,
        passphrase: String?,
        scope: RecoveryScopeToken,
        progress: RecoveryProgressSink? = nil
    ) async throws -> RecoveryReceipt {
        guard scope.kind == .authenticated else { throw RecoveryFailure.invalidScope }
        guard isScopeCurrent(scope) else { throw RecoveryFailure.scopeChanged }

        activeScope = scope
        state = .running(.downloading)
        let weakBox = WeakRecoveryCoordinatorBox(self)
        do {
            let receipt = try await withTaskTimeout(seconds: timeoutSeconds) {
                try await self.backupManager.restoreVersionVerified(
                    recordName: recordName,
                    passphrase: passphrase,
                    progress: { stage in
                        await MainActor.run {
                            guard let self = weakBox.value, self.isScopeCurrent(scope) else { return }
                            self.state = .running(stage)
                        }
                        await progress?(stage)
                    }
                )
            }
            guard isScopeCurrent(scope) else { throw RecoveryFailure.scopeChanged }
            state = .succeeded(receipt)
            return receipt
        } catch let failure as RecoveryFailure {
            state = .failed(failure)
            throw failure
        } catch is CancellationError {
            state = .cancelled
            throw RecoveryFailure.cancelled
        } catch {
            let failure = RecoveryFailure.underlying(message: Self.safeReasonCode(for: error))
            state = .failed(failure)
            throw failure
        }
    }

    func retry() async {
        guard let scope = activeScope else { return }
        await discover(scope: scope)
    }

    func cancel() {
        guard case .running(let stage) = state else {
            cancelActiveOperation(publishCancellation: true)
            return
        }
        switch stage {
        case .searching, .downloading, .validating:
            cancelActiveOperation(publishCancellation: true)
        case .importing, .verifying, .finishing:
            break
        }
    }

    func reset() {
        cancelActiveOperation(publishCancellation: false)
        activeScope = nil
        state = .idle
    }

    private func cancelActiveOperation(publishCancellation: Bool) {
        operationGeneration &+= 1
        task?.cancel()
        task = nil
        if publishCancellation { state = .cancelled }
    }

    nonisolated private static func safeReasonCode(for error: Error) -> String {
        switch error {
        case is AppError: "app_error"
        default: "unknown_error"
        }
    }
}

private final class WeakRecoveryCoordinatorBox: @unchecked Sendable {
    weak var value: RecoveryCoordinator?

    init(_ value: RecoveryCoordinator) {
        self.value = value
    }
}
