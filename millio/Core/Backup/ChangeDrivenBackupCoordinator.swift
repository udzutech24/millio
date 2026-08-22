import Foundation

@MainActor
final class ChangeDrivenBackupCoordinator {
    private let eventBus: EventBus
    private let debounceNanoseconds: UInt64
    private let canBackup: () -> Bool
    private let backup: () async throws -> Void

    private var subscriptionID: UUID?
    private var debounceTask: Task<Void, Never>?
    private var backupTask: Task<Void, Never>?
    private(set) var isDirty = false

    init(
        eventBus: EventBus? = nil,
        debounceNanoseconds: UInt64 = 30_000_000_000,
        canBackup: @escaping () -> Bool,
        backup: @escaping () async throws -> Void
    ) {
        self.eventBus = eventBus ?? .shared
        self.debounceNanoseconds = debounceNanoseconds
        self.canBackup = canBackup
        self.backup = backup
    }

    func start() {
        guard subscriptionID == nil else { return }
        subscriptionID = eventBus.subscribe { [weak self] event in
            guard Self.isBackupRelevant(event) else { return }
            self?.markDirty()
        }
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        backupTask?.cancel()
        backupTask = nil
        if let subscriptionID {
            eventBus.unsubscribe(subscriptionID)
            self.subscriptionID = nil
        }
    }

    func markDirty() {
        isDirty = true
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: debounceNanoseconds)
            } catch {
                return
            }
            await flushIfNeeded()
        }
    }

    func flushIfNeeded() async {
        guard isDirty, canBackup() else { return }
        if let backupTask {
            await backupTask.value
            return
        }

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await backup()
                isDirty = false
            } catch {
                AppLogger.log(
                    .warning,
                    category: "Backup",
                    "Change-driven backup deferred code=backup_failed"
                )
            }
            backupTask = nil
        }
        backupTask = task
        await task.value
    }

    nonisolated static func isBackupRelevant(_ event: AppEvent) -> Bool {
        switch event {
        case FinanceEvent.cardsUpdated,
             FinanceEvent.creditsUpdated,
             FinanceEvent.investmentsUpdated,
             FinanceEvent.transactionsUpdated,
             FinanceEvent.auditSnapshotsUpdated,
             FinanceEvent.depositOperationCommitted:
            true
        default:
            false
        }
    }
}
