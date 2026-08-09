import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Account product backup", .serialized)
struct AccountProductBackupTests {
    @Test("Known and unknown product identity survive Account backup import") @MainActor
    func productIdentityRoundTrip() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext

        let known = Account(name: "Card", kind: .debitCard, productType: .creditCard)
        known.cardMeta = Self.cardMeta(creditLimit: 100_000)
        let unknown = Account(name: "Legacy cash", kind: .cash, productType: .unknownLegacy)
        unknown.productMigrationReason = ProductMigrationReason.ambiguousCashKind.rawValue

        for source in [known, unknown] {
            let data = try source.export()
            let dictionary = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            try AccountImporter.import(from: dictionary, context: context)
        }
        try context.save()

        let restored = try context.fetch(FetchDescriptor<Account>())
        #expect(restored.count == 2)
        #expect(restored.first(where: { $0.name == "Card" })?.productType == .creditCard)
        #expect(restored.first(where: { $0.name == "Card" })?.cardMeta?.creditLimit == 100_000)
        #expect(restored.first(where: { $0.name == "Legacy cash" })?.productType == .unknownLegacy)
        #expect(restored.first(where: { $0.name == "Legacy cash" })?.productMigrationReason
            == ProductMigrationReason.ambiguousCashKind.rawValue)
    }

    @Test("Old backup without product columns is classified during import") @MainActor
    func oldBackupWithoutProductColumns() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = UUID()
        let dictionary: [String: Any] = [
            "type": "Account",
            "id": id.uuidString,
            "name": "Old",
            "kindRaw": AccountKind.cash.rawValue,
            "currency": "RUB",
            "createdAt": Date(timeIntervalSince1970: 1_700_000_000).timeIntervalSince1970,
            "includeInTotal": true,
            "order": 0
        ]

        try AccountImporter.import(from: dictionary, context: context)
        try context.save()
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        #expect(account.id == id)
        #expect(account.productType == .unknownLegacy)
        #expect(account.productMigrationReason == ProductMigrationReason.ambiguousCashKind.rawValue)
    }

    @Test("Contradictory product tuple is rejected before an existing row is mutated") @MainActor
    func invalidImportDoesNotMutateExistingAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let existing = Account(name: "Original", kind: .cash, productType: .cash)
        context.insert(existing)
        try context.save()

        let dictionary: [String: Any] = [
            "type": "Account",
            "id": existing.id.uuidString,
            "name": "Corrupted",
            "kindRaw": AccountKind.loan.rawValue,
            "productTypeRaw": AccountProductType.cash.rawValue,
            "currency": "USD",
            "createdAt": Date().timeIntervalSince1970,
            "includeInTotal": true,
            "order": 100,
            "loanMeta": Self.validLoan().exportDict()
        ]

        #expect(throws: (any Error).self) {
            try AccountImporter.import(from: dictionary, context: context)
        }
        #expect(existing.name == "Original")
        #expect(existing.kind == .cash)
        #expect(existing.productType == .cash)
        #expect(existing.currency == "RUB")
        #expect(existing.order == 0)
    }

    @Test("Non-replay-compatible unknownLegacy backup is rejected") @MainActor
    func invalidUnknownLegacyBackupIsRejected() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let dictionary: [String: Any] = [
            "type": "Account",
            "id": UUID().uuidString,
            "name": "Broken deposit",
            "kindRaw": AccountKind.deposit.rawValue,
            "productTypeRaw": AccountProductType.unknownLegacy.rawValue,
            "productMigrationReason": ProductMigrationReason.invalidDepositMeta.rawValue,
            "currency": "RUB",
            "createdAt": Date().timeIntervalSince1970,
            "includeInTotal": true,
            "order": 0
        ]

        #expect(throws: (any Error).self) {
            try AccountImporter.import(from: dictionary, context: container.mainContext)
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<Account>()).isEmpty)
    }

    @Test("Old upsert cannot downgrade a newer coupled product tuple") @MainActor
    func oldPayloadPreservesExistingProductKindAndMeta() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let existing = Account(name: "House", kind: .manualAsset, productType: .realEstate)
        existing.manualAssetMeta = ManualAssetMeta(
            revalReminderMonths: 12,
            depreciationRatePerYear: nil,
            linkedLoanID: nil
        )
        context.insert(existing)
        try context.save()

        let oldPayload: [String: Any] = [
            "type": "Account",
            "id": existing.id.uuidString,
            "name": "Renamed by restore",
            "kindRaw": AccountKind.cash.rawValue,
            "currency": "RUB",
            "createdAt": existing.createdAt.timeIntervalSince1970,
            "includeInTotal": true,
            "order": 0
        ]
        try AccountImporter.import(from: oldPayload, context: context)

        #expect(existing.name == "Renamed by restore")
        #expect(existing.productType == .realEstate)
        #expect(existing.kind == .manualAsset)
        #expect(existing.manualAssetMeta?.revalReminderMonths == 12)
        #expect(existing.cardMeta == nil)
    }

    private static func cardMeta(creditLimit: Decimal?) -> CardMeta {
        CardMeta(
            bank: nil,
            last4: nil,
            creditLimit: creditLimit,
            statementDay: nil,
            dueDay: nil,
            minPayment: nil,
            graceDays: nil,
            overdraftLimit: nil
        )
    }

    private static func validLoan() -> LoanMeta {
        LoanMeta(
            principal: 100,
            rate: 5,
            monthlyPayment: nil,
            paymentDay: nil,
            termEnd: nil,
            scheduleType: .annuity,
            insurance: nil
        )
    }
}
