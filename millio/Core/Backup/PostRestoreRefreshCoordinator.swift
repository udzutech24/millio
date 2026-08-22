import Foundation

@MainActor
final class PostRestoreRefreshCoordinator {
    private let eventBus: EventBus
    private let refresh: (RecoveryReceipt) -> Void
    private var subscriptionID: UUID?
    private var lastReceiptID: UUID?

    init(
        eventBus: EventBus? = nil,
        refresh: @escaping (RecoveryReceipt) -> Void
    ) {
        self.eventBus = eventBus ?? .shared
        self.refresh = refresh
    }

    func start() {
        guard subscriptionID == nil else { return }
        subscriptionID = eventBus.subscribe { [weak self] event in
            guard let self, case BackupEvent.restoreVerified(let receipt) = event else { return }
            guard receipt.id != lastReceiptID else { return }
            lastReceiptID = receipt.id
            refresh(receipt)
        }
    }

    func stop() {
        if let subscriptionID {
            eventBus.unsubscribe(subscriptionID)
            self.subscriptionID = nil
        }
    }
}

