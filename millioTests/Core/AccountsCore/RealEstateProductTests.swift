import Foundation
import ImageIO
import SwiftData
import SwiftUI
import Testing
import UIKit
@testable import millio

@Suite("Real estate product", .serialized)
struct RealEstateProductTests {
    @Test("Property types use static translated titles in RU, EN and zh-Hans")
    func propertyTypeLocalization() {
        LanguageManager.withLockedLanguageMutation {
            let original = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(original) }
            for language in [Language.russian, .english, .simplifiedChinese] {
                LanguageManager.shared.setLanguage(language)
                let titles = RealEstatePropertyType.allCases.map(\.localizedTitle)
                #expect(titles.count == 5)
                #expect(titles.allSatisfy { !$0.isEmpty && !$0.hasPrefix("real_estate.") })
                #expect(Set(titles).count == 5)
            }
        }
    }

    @Test("Reminder policy exposes only supported persisted intervals")
    func reminderPolicy() {
        #expect(RealEstateReminder.allCases.map(\.persistedMonths) == [nil, 3, 6, 12, 24])
        #expect(RealEstateReminder(persistedMonths: 7) == .off)
    }

    @Test("Mortgage policy accepts only active same-currency loans")
    func mortgagePolicy() {
        let property = Account(name: "Home", kind: .manualAsset, productType: .realEstate, currency: "RUB")
        let loan = Account(name: "Mortgage", kind: .loan, productType: .loan, currency: "RUB")
        #expect(RealEstateEditPolicy.eligibleMortgage(loan, for: property))
        loan.currency = "USD"
        #expect(!RealEstateEditPolicy.eligibleMortgage(loan, for: property))
        loan.currency = "RUB"; loan.archivedAt = Date()
        #expect(!RealEstateEditPolicy.eligibleMortgage(loan, for: property))
    }

    @Test("Archived real estate is read-only")
    func archivedEditPolicy() {
        #expect(!RealEstateEditPolicy.isReadOnly(archivedAt: nil, deletedAt: nil))
        #expect(RealEstateEditPolicy.isReadOnly(archivedAt: Date(), deletedAt: nil))
        #expect(RealEstateEditPolicy.isReadOnly(archivedAt: nil, deletedAt: Date()))
    }

    @Test("Metadata and gallery rollback together when edit save fails") @MainActor
    func atomicEditRollback() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Before", kind: .manualAsset, productType: .realEstate, currency: "RUB")
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
        let profile = RealEstateProfile(accountID: account.id, propertyType: .apartment)
        let originalPhoto = AccountAttachment(accountID: account.id, order: 0, isCover: true, mediaData: Data([1]))
        context.insert(account); context.insert(profile); context.insert(originalPhoto)
        try context.save()

        let service = RealEstateEditorService(modelContext: context, saveOperation: { _ in throw InjectedError.failure })
        #expect(throws: InjectedError.failure) {
            try service.update(
                account: account, name: "After", group: nil, note: nil, includeInTotal: false,
                propertyType: .house, reminderMonths: 6, linkedLoanID: nil,
                photos: [RealEstatePhotoDraft(data: Data([2]), isCover: true)]
            )
        }
        #expect(account.name == "Before")
        #expect(try context.fetch(FetchDescriptor<RealEstateProfile>()).first?.propertyType == .apartment)
        #expect(try context.fetch(FetchDescriptor<AccountAttachment>()).map(\.mediaData) == [Data([1])])
    }

    @Test("Edited photos persist after a fresh fetch") @MainActor
    func editedPhotosReopen() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Home", kind: .manualAsset, productType: .realEstate, currency: "RUB")
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
        context.insert(account); context.insert(RealEstateProfile(accountID: account.id, propertyType: .apartment)); try context.save()
        try RealEstateEditorService(modelContext: context).update(
            account: account, name: "Home", group: nil, note: nil, includeInTotal: true,
            propertyType: .apartment, reminderMonths: 12, linkedLoanID: nil,
            photos: [RealEstatePhotoDraft(data: Data([7, 8]), isCover: true)]
        )
        let reopened = try AccountAttachmentService(modelContext: context).photos(accountID: account.id)
        #expect(reopened.count == 1)
        #expect(reopened[0].mediaData == Data([7, 8]))
        #expect(reopened[0].isCover)
    }

    @Test("Edit sheet renders 375/390, three languages and regular/accessibility Dynamic Type") @MainActor
    func editRenderMatrix() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Family apartment", kind: .manualAsset, productType: .realEstate, currency: "RUB")
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: 6, depreciationRatePerYear: nil, linkedLoanID: nil)
        context.insert(account); context.insert(RealEstateProfile(accountID: account.id, propertyType: .commercial)); try context.save()

        LanguageManager.withLockedLanguageMutation {
            let original = LanguageManager.shared.currentLanguage
            defer { LanguageManager.shared.setLanguage(original) }
            for language in [Language.russian, .english, .simplifiedChinese] {
                LanguageManager.shared.setLanguage(language)
                let visibleTypedStrings = RealEstatePropertyType.allCases.map(\.localizedTitle)
                    + RealEstateReminder.allCases.map(\.localizedTitle)
                #expect(visibleTypedStrings.allSatisfy { !$0.hasPrefix("real_estate.") })
                for (width, height) in [(375.0, 812.0), (390.0, 844.0)] {
                    for sizeCategory in [ContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
                        let view = RealEstateEditSheet(account: account, modelContext: context) { _, _, _, _, _, _, _, _ in }
                            .frame(width: width, height: height)
                            .preferredColorScheme(.dark)
                            .environment(\.sizeCategory, sizeCategory)
                            .modelContainer(container)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 1
                        #expect(renderer.uiImage != nil)
                    }
                }
            }
        }
    }
    private enum InjectedError: Error { case failure }

    @Test("Descriptor uses product identity, not generic manual-asset kind") @MainActor
    func descriptorUsesProductIdentity() {
        let realEstate = Account(name: "Home", kind: .manualAsset, productType: .realEstate)
        let business = Account(name: "Business", kind: .manualAsset, productType: .business)
        #expect(AccountDetailDescriptor.resolve(for: realEstate).kind == .realEstate)
        #expect(AccountDetailDescriptor.resolve(for: business).kind == .generic)
    }

    @Test("Valuation summary uses append-only opening and revaluation events") @MainActor
    func valuationSummary() {
        let account = Account(name: "Home", kind: .manualAsset, productType: .realEstate)
        let first = AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_000_000), type: .openingBalance, amount: 10_000_000)
        let second = AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_086_400), type: .revaluation, amount: 12_000_000, note: "Independent appraisal")
        let summary = RealEstateValuationCalculator.summary(events: [second, first], now: Date(timeIntervalSince1970: 1_700_172_800))
        #expect(summary.currentValue == 12_000_000)
        #expect(summary.previousValue == 10_000_000)
        #expect(summary.delta == 2_000_000)
        #expect(summary.percentDelta == 20)
        #expect(summary.ageInDays == 1)
    }

    @Test("Photo processor downsamples and strips source metadata")
    func photoProcessor() async throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 3_000, height: 2_000))
        let source = renderer.jpegData(withCompressionQuality: 1) { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3_000, height: 2_000))
        }
        let output = try await AccountPhotoProcessor().process(source)
        #expect(output.count <= AccountPhotoProcessor.maximumEncodedBytes)
        let imageSource = try #require(CGImageSourceCreateWithData(output as CFData, nil))
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any])
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        #expect(max(width, height) <= AccountPhotoProcessor.maximumPixelDimension)
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
    }

    @Test("Gallery enforces limit, cover and stable order") @MainActor
    func galleryMutations() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let accountID = UUID()
        let service = AccountAttachmentService(modelContext: context)
        var photos: [AccountAttachment] = []
        for index in 0..<AccountAttachmentPolicy.maximumPhotos {
            photos.append(try service.addPhoto(accountID: accountID, processedData: Data([UInt8(index + 1)])))
        }
        #expect(photos.first?.isCover == true)
        #expect(throws: AccountAttachmentServiceError.photoLimitReached) {
            try service.addPhoto(accountID: accountID, processedData: Data([9]))
        }
        try service.setCover(photos[2])
        #expect(try service.photos(accountID: accountID).filter(\.isCover).map(\.id) == [photos[2].id])
        try service.reorder(accountID: accountID, orderedIDs: photos.reversed().map(\.id))
        #expect(try service.photos(accountID: accountID).map(\.id) == photos.reversed().map(\.id))
        try service.delete(photos[2])
        let remaining = try service.photos(accountID: accountID)
        #expect(remaining.count == 4)
        #expect(remaining.filter(\.isCover).count == 1)
        #expect(remaining.map(\.order) == Array(0..<4))
    }

    @Test("Profile and attachment survive full backup round-trip") @MainActor
    func backupRoundTrip() throws {
        AccountsCoreFeatureRegistration.register()
        let sourceContainer = try AppMigrationPlan.makeInMemoryContainer()
        let source = sourceContainer.mainContext
        let account = Account(name: "Home", kind: .manualAsset, productType: .realEstate)
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
        source.insert(account)
        source.insert(RealEstateProfile(accountID: account.id, propertyType: .apartment))
        source.insert(AccountAttachment(accountID: account.id, order: 0, isCover: true, mediaData: Data([1, 2, 3])))
        try source.save()
        let backup = try DataRepository.exportAllData(from: source)

        let targetContainer = try AppMigrationPlan.makeInMemoryContainer()
        try DataRepository.importAllData(backup, into: targetContainer.mainContext)
        #expect(try targetContainer.mainContext.fetch(FetchDescriptor<RealEstateProfile>()).first?.propertyType == .apartment)
        #expect(try targetContainer.mainContext.fetch(FetchDescriptor<AccountAttachment>()).first?.mediaData == Data([1, 2, 3]))
    }

    @Test("Account, profile and photos share one atomic creation boundary") @MainActor
    func atomicCreationRollback() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let command = CreateProductCommand(
            productType: .realEstate,
            name: "Home",
            currency: "RUB",
            openingBalance: 1,
            metadata: AccountProductMetadata(manualAsset: ManualAssetMeta(
                revalReminderMonths: nil,
                depreciationRatePerYear: nil,
                linkedLoanID: nil
            ))
        )
        let factory = AccountProductFactory(modelContext: context)
        #expect(throws: InjectedError.failure) {
            try factory.create(command, graphEnricher: { graph, transactionContext in
                transactionContext.insert(RealEstateProfile(accountID: graph.account.id, propertyType: .house))
                throw InjectedError.failure
            })
        }
        #expect(try context.fetch(FetchDescriptor<Account>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<RealEstateProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountAttachment>()).isEmpty)
    }

    @Test("Archive preserves gallery; physical delete removes V8 product records") @MainActor
    func lifecycleSemantics() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Home", kind: .manualAsset, productType: .realEstate)
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: nil, depreciationRatePerYear: nil, linkedLoanID: nil)
        context.insert(account)
        context.insert(RealEstateProfile(accountID: account.id, propertyType: .apartment))
        context.insert(AccountAttachment(accountID: account.id, order: 0, isCover: true, mediaData: Data([1])))
        try context.save()
        let service = AccountsCoreService(modelContext: context)

        try service.archiveAccount(account)
        #expect(try context.fetch(FetchDescriptor<RealEstateProfile>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<AccountAttachment>()).count == 1)

        try service.physicallyDelete(account)
        #expect(try context.fetch(FetchDescriptor<RealEstateProfile>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<AccountAttachment>()).isEmpty)
    }

    @Test("Detail renders in dark mode with accessibility Dynamic Type") @MainActor
    func detailVisualSmoke() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Apartment", kind: .manualAsset, productType: .realEstate)
        account.manualAssetMeta = ManualAssetMeta(revalReminderMonths: 12, depreciationRatePerYear: nil, linkedLoanID: nil)
        context.insert(account)
        context.insert(AccountEvent(account: account, date: Date(), type: .openingBalance, amount: 54_000_000))
        context.insert(RealEstateProfile(accountID: account.id, propertyType: .apartment))
        try context.save()

        let view = ScrollView {
            RealEstateDetailSection(account: account, modelContext: context, refreshToken: UUID())
                .padding()
        }
        .frame(width: 390, height: 844)
        .preferredColorScheme(.dark)
        .environment(\.sizeCategory, .accessibilityExtraExtraExtraLarge)
        .modelContainer(container)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        #expect(renderer.uiImage != nil)
    }
}
