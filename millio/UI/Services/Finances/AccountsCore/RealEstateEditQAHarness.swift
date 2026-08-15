#if DEBUG
import SwiftData
import SwiftUI
import UIKit

/// Opt-in simulator harness for the real production editor. It never runs without the explicit
/// QA environment flag checked by `RootTabView` and contains no release-only behavior.
struct RealEstateEditQAHarness: View {
    let modelContext: ModelContext
    @State private var account: Account?

    var body: some View {
        Group {
            if let account {
                let mode = ProcessInfo.processInfo.environment["MILLIO_REAL_ESTATE_QA_MODE"]
                if mode == "detail" {
                    NavigationStack {
                        AccountDetailView(account: account, modelContext: modelContext)
                    }
                } else {
                    RealEstateEditSheet(
                        account: account,
                        modelContext: modelContext,
                        startsWithTypePicker: mode == "type",
                        startsExpanded: mode == "additional" || mode == "reminder" || mode == "mortgage",
                        startsWithReminderPicker: mode == "reminder",
                        startsWithMortgagePicker: mode == "mortgage"
                    ) { _, _, _, _, _, _, _, _ in }
                }
            } else {
                ProgressView().task { seed() }
            }
        }
        .preferredColorScheme(.dark)
    }

    @MainActor private func seed() {
        // Dedicated screenshot simulators may relaunch this harness many times; keep the fixture
        // deterministic. This path is DEBUG-only and unreachable without the explicit QA flag.
        try? modelContext.delete(model: AccountAttachment.self)
        try? modelContext.delete(model: RealEstateProfile.self)
        try? modelContext.delete(model: AccountEvent.self)
        try? modelContext.delete(model: Account.self)
        try? modelContext.save()
        let property = Account(
            name: L("real_estate.qa.property_name"),
            kind: .manualAsset,
            productType: .realEstate,
            currency: "RUB"
        )
        property.manualAssetMeta = ManualAssetMeta(revalReminderMonths: 6, depreciationRatePerYear: nil, linkedLoanID: nil)
        modelContext.insert(property)
        modelContext.insert(RealEstateProfile(accountID: property.id, propertyType: .apartment))
        modelContext.insert(AccountEvent(
            account: property,
            date: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date(),
            type: .openingBalance,
            amount: 52_000_000
        ))
        modelContext.insert(AccountEvent(
            account: property,
            date: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date(),
            type: .revaluation,
            amount: 54_000_000
        ))
        if let photoData = qaCoverPhotoData() {
            modelContext.insert(AccountAttachment(
                accountID: property.id,
                order: 0,
                isCover: true,
                mediaData: photoData
            ))
        }
        let mortgage = Account(name: L("real_estate.qa.mortgage_name"), kind: .loan, productType: .loan, currency: "RUB")
        modelContext.insert(mortgage)
        try? modelContext.save()
        account = property
    }

    private func qaCoverPhotoData() -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_200, height: 800))
        return renderer.jpegData(withCompressionQuality: 0.9) { context in
            UIColor(red: 0.12, green: 0.31, blue: 0.52, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 800))
            UIColor(red: 0.31, green: 0.63, blue: 0.84, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1_200, height: 430))
            UIColor(red: 0.08, green: 0.16, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(x: 130, y: 270, width: 940, height: 530))
            UIColor(red: 0.91, green: 0.72, blue: 0.31, alpha: 1).setFill()
            for column in 0..<7 {
                for row in 0..<4 {
                    context.fill(CGRect(x: 190 + column * 125, y: 330 + row * 100, width: 58, height: 54))
                }
            }
        }
    }
}
#endif
