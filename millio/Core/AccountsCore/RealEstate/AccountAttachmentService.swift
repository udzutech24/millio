import Foundation
import SwiftData

enum AccountAttachmentServiceError: Error, Equatable {
    case photoLimitReached
    case attachmentNotFound
    case invalidOrder
}

enum AccountAttachmentPolicy {
    static let maximumPhotos = 5
}

@MainActor
struct AccountAttachmentService {
    let modelContext: ModelContext

    func photos(accountID: UUID) throws -> [AccountAttachment] {
        let descriptor = FetchDescriptor<AccountAttachment>(
            predicate: #Predicate { $0.accountID == accountID },
            sortBy: [SortDescriptor(\AccountAttachment.order), SortDescriptor(\AccountAttachment.createdAt)]
        )
        return try modelContext.fetch(descriptor).filter { $0.kind == .photo }
    }

    @discardableResult
    func addPhoto(accountID: UUID, processedData: Data) throws -> AccountAttachment {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        let existing = try photos(accountID: accountID)
        guard existing.count < AccountAttachmentPolicy.maximumPhotos else {
            throw AccountAttachmentServiceError.photoLimitReached
        }
        let attachment = AccountAttachment(
            accountID: accountID,
            order: existing.count,
            isCover: existing.isEmpty,
            mediaData: processedData
        )
        modelContext.insert(attachment)
        try saveOrRollback()
        return attachment
    }

    func setCover(_ attachment: AccountAttachment) throws {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        let existing = try photos(accountID: attachment.accountID)
        guard existing.contains(where: { $0.id == attachment.id }) else {
            throw AccountAttachmentServiceError.attachmentNotFound
        }
        existing.forEach { $0.isCover = $0.id == attachment.id }
        try saveOrRollback()
    }

    func reorder(accountID: UUID, orderedIDs: [UUID]) throws {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        let existing = try photos(accountID: accountID)
        guard Set(existing.map(\.id)) == Set(orderedIDs), existing.count == orderedIDs.count else {
            throw AccountAttachmentServiceError.invalidOrder
        }
        let byID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for (index, id) in orderedIDs.enumerated() { byID[id]?.order = index }
        try saveOrRollback()
    }

    func delete(_ attachment: AccountAttachment) throws {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        let accountID = attachment.accountID
        let wasCover = attachment.isCover
        modelContext.delete(attachment)
        var remaining = try photos(accountID: accountID).filter { $0.id != attachment.id }
        remaining.sort { $0.order < $1.order }
        for (index, item) in remaining.enumerated() { item.order = index }
        if wasCover, let first = remaining.first { first.isCover = true }
        try saveOrRollback()
    }

    private func saveOrRollback() throws {
        do { try modelContext.save() } catch {
            modelContext.rollback()
            throw error
        }
    }
}
