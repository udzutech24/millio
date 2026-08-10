import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("Credit-card atomic editor")
@MainActor
struct CreditCardEditorServiceTests {
    private func makeCard() throws -> (ModelContainer, ModelContext, Account) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let id = try AccountProductFactory(modelContext: context).create(CreateProductCommand(
            productType: .creditCard,
            name: "Old",
            currency: "RUB",
            openingBalance: 100_000,
            metadata: .init(card: CardMeta(
                bank: "old", last4: "1111", creditLimit: 100_000, statementDay: 1,
                dueDay: 20, minPayment: 1_000, graceDays: 55, overdraftLimit: nil
            ))
        ))
        return (container, context, try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == id }))
    }

    private func command(name: String = "New") -> CreditCardEditCommand {
        CreditCardEditCommand(
            name: name, group: nil, note: "note", includeInTotal: false, bank: "new",
            last4: "4242", creditLimit: 200_000, statementDay: 5, dueDay: 25,
            minPayment: 2_000, graceDays: 60
        )
    }

    @Test("Account and CardMeta commit together")
    func atomicSuccess() throws {
        let (container, context, card) = try makeCard()
        _ = container
        try CreditCardEditorService(modelContext: context).update(account: card, command: command())
        #expect(card.name == "New")
        #expect(card.includeInTotal == false)
        #expect(card.cardMeta?.bank == "new")
        #expect(card.cardMeta?.last4 == "4242")
        #expect(card.cardMeta?.creditLimit == 200_000)
        #expect(card.cardMeta?.statementDay == 5)
        #expect(card.cardMeta?.dueDay == 25)
        #expect(card.cardMeta?.minPayment == 2_000)
        #expect(card.cardMeta?.graceDays == 60)
        #expect(card.currency == "RUB")
    }

    @Test("Save failure rolls Account and metadata back together")
    func atomicRollback() throws {
        struct Failure: Error {}
        let (container, context, card) = try makeCard()
        _ = container
        let service = CreditCardEditorService(modelContext: context, saveOperation: { _ in throw Failure() })
        #expect(throws: Failure.self) { try service.update(account: card, command: command()) }
        let restored = try #require(context.fetch(FetchDescriptor<Account>()).first { $0.id == card.id })
        #expect(restored.name == "Old")
        #expect(restored.includeInTotal)
        #expect(restored.cardMeta?.bank == "old")
        #expect(restored.cardMeta?.creditLimit == 100_000)
        #expect(!context.hasChanges)
    }

    @Test("Validation rejects malformed terms")
    func validation() {
        let invalidLast4 = CreditCardEditCommand(
            name: "Card", group: nil, note: nil, includeInTotal: true, bank: nil,
            last4: "12A4", creditLimit: 1, statementDay: nil, dueDay: nil,
            minPayment: nil, graceDays: nil
        )
        #expect(throws: CreditCardEditorError.invalidLast4) { try CreditCardEditPolicy.validate(invalidLast4) }
        #expect(throws: CreditCardEditorError.invalidName) { try CreditCardEditPolicy.validate(command(name: " ")) }
    }

    @Test("Archived card is read-only")
    func archivedReadOnly() throws {
        let (container, context, card) = try makeCard()
        _ = container
        card.archivedAt = .now
        try context.save()
        #expect(throws: CreditCardEditorError.readOnly) {
            try CreditCardEditorService(modelContext: context).update(account: card, command: command())
        }
    }
}
