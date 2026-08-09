import Foundation
import SwiftData

enum RealEstateEditorError: Error {
    case readOnly
    case invalidName
    case invalidMortgage
}

@MainActor
struct RealEstateProfileService {
    let modelContext: ModelContext

    func profile(accountID: UUID) throws -> RealEstateProfile? {
        let descriptor = FetchDescriptor<RealEstateProfile>(predicate: #Predicate { $0.accountID == accountID })
        return try modelContext.fetch(descriptor).first
    }

    @discardableResult
    func upsert(account: Account, propertyType: RealEstatePropertyType) throws -> RealEstateProfile {
        guard account.productType == .realEstate else { throw AccountsCoreServiceError.missingProductIdentity }
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        let result: RealEstateProfile
        if let existing = try profile(accountID: account.id) {
            existing.propertyType = propertyType
            result = existing
        } else {
            let created = RealEstateProfile(accountID: account.id, propertyType: propertyType)
            modelContext.insert(created)
            result = created
        }
        do { try modelContext.save() } catch {
            modelContext.rollback()
            throw error
        }
        return result
    }
}

@MainActor
struct RealEstateEditorService {
    let modelContext: ModelContext
    var saveOperation: (ModelContext) throws -> Void = { try $0.save() }

    func update(
        account: Account,
        name: String,
        group: AccountGroup?,
        note: String?,
        includeInTotal: Bool,
        propertyType: RealEstatePropertyType,
        reminderMonths: Int?,
        linkedLoanID: UUID?,
        photos: [RealEstatePhotoDraft]
    ) throws {
        guard !modelContext.hasChanges else { throw AccountsCoreServiceError.dirtyContext }
        guard account.productType == .realEstate else { throw AccountsCoreServiceError.missingProductIdentity }
        guard !RealEstateEditPolicy.isReadOnly(archivedAt: account.archivedAt, deletedAt: account.deletedAt) else {
            throw RealEstateEditorError.readOnly
        }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RealEstateEditorError.invalidName
        }
        guard photos.count <= AccountAttachmentPolicy.maximumPhotos else {
            throw AccountAttachmentServiceError.photoLimitReached
        }
        if let linkedLoanID {
            let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == linkedLoanID })
            guard let loan = try modelContext.fetch(descriptor).first,
                  RealEstateEditPolicy.eligibleMortgage(loan, for: account) else {
                throw RealEstateEditorError.invalidMortgage
            }
        }
        let metadata = ManualAssetMeta(
            revalReminderMonths: reminderMonths,
            depreciationRatePerYear: account.manualAssetMeta?.depreciationRatePerYear,
            linkedLoanID: linkedLoanID
        )
        try ProductDefinitionCatalog.validateStoredIdentity(
            .realEstate,
            kindRaw: account.kindRaw,
            metadata: AccountProductMetadata(manualAsset: metadata),
            migrationReason: nil
        )
        let membershipChanged = account.includeInTotal != includeInTotal
        account.name = name
        account.group = group
        account.note = note
        account.includeInTotal = includeInTotal
        account.manualAssetMeta = metadata
        let profileService = RealEstateProfileService(modelContext: modelContext)
        let profile: RealEstateProfile
        if let existing = try profileService.profile(accountID: account.id) {
            profile = existing
        } else {
            profile = RealEstateProfile(accountID: account.id, propertyType: propertyType)
            modelContext.insert(profile)
        }
        profile.propertyType = propertyType
        let existingPhotos = try AccountAttachmentService(modelContext: modelContext).photos(accountID: account.id)
        existingPhotos.forEach(modelContext.delete)
        for (index, photo) in photos.enumerated() {
            modelContext.insert(AccountAttachment(
                id: photo.id,
                accountID: account.id,
                order: index,
                isCover: photo.isCover || (index == 0 && !photos.contains(where: \.isCover)),
                mediaData: photo.data
            ))
        }
        var revisions: Set<HistoricalValuationRevisionDimension> = [.financial]
        if membershipChanged { revisions.insert(.accountSet) }
        HistoricalValuationRevisionTracker.bump(revisions, on: account)
        do { try saveOperation(modelContext) } catch {
            modelContext.rollback()
            throw error
        }
    }
}
