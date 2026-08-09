#if DEBUG
import SwiftData
import SwiftUI

/// Opt-in simulator harness for the real production editor. It never runs without the explicit
/// QA environment flag checked by `RootTabView` and contains no release-only behavior.
struct RealEstateEditQAHarness: View {
    let modelContext: ModelContext
    @State private var account: Account?

    var body: some View {
        Group {
            if let account {
                let mode = ProcessInfo.processInfo.environment["MILLIO_REAL_ESTATE_QA_MODE"]
                RealEstateEditSheet(
                    account: account,
                    modelContext: modelContext,
                    startsWithTypePicker: mode == "type",
                    startsExpanded: mode == "additional" || mode == "reminder" || mode == "mortgage",
                    startsWithReminderPicker: mode == "reminder",
                    startsWithMortgagePicker: mode == "mortgage"
                ) { _, _, _, _, _, _, _, _ in }
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
        let mortgage = Account(name: L("real_estate.qa.mortgage_name"), kind: .loan, productType: .loan, currency: "RUB")
        modelContext.insert(mortgage)
        try? modelContext.save()
        account = property
    }
}
#endif
