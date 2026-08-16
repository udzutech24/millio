import Foundation
import UniformTypeIdentifiers

enum IncomingStatementReadiness: Equatable {
    case ready
    case locked
    case storeUnavailable
    case modalBusy
}

@MainActor
final class IncomingStatementCoordinator {
    private let inbox: IncomingStatementInbox

    init(inbox: IncomingStatementInbox) {
        self.inbox = inbox
    }

    static func appGroup() throws -> IncomingStatementCoordinator {
        try .init(inbox: .appGroup())
    }

    func stageDirectURL(_ url: URL) throws -> IncomingStatementInboxItem {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType
        return try inbox.enqueue(sourceURL: url, declaredType: type)
    }

    func nextItem(readiness: IncomingStatementReadiness) throws -> IncomingStatementInboxItem? {
        guard readiness == .ready else { return nil }
        try inbox.cleanupExpired()
        return try inbox.queuedItems().first
    }

    func complete(_ item: IncomingStatementInboxItem) throws {
        try inbox.discard(item)
    }

    func discard(_ item: IncomingStatementInboxItem) throws {
        try inbox.discard(item)
    }
}
