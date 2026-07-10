import Foundation
import Testing
@testable import millio

/// Транзиентный value-DTO формы «Карта/Счёт» (6b Ф5c.2, замена легаси-@Model-карты в биндингах).
/// Гарды на byte-for-byte-поведение: дефолты должны совпадать с легаси-`Card.init`, а computed-пары
/// `cardType`/`cardTypeRaw` и `priority`/`priorityRaw` — зеркалить модель, иначе EDIT-путь
/// (`FinanceAddAccountView.makeLegacyCard` → `CardViewModel.updateCard`) сохранит не то, что показала форма.
@Suite("InlineCardDraft (6b Ф5c.2)")
struct InlineCardDraftTests {

    @Test("Дефолты драфта совпадают с легаси-Card.init")
    func defaultsMatchLegacyCardDefaults() {
        let draft = InlineCardDraft(name: "Visa", currency: "USD")

        #expect(draft.cardNumber == "")
        #expect(draft.bank == .other)
        #expect(draft.cardType == .debit)
        #expect(draft.priority == .normal)
        #expect(draft.balance == 0.0)
        #expect(draft.creditLimit == nil)
        #expect(draft.expiryDate == nil)
        #expect(draft.cardholderName == nil)
        #expect(draft.cardColor == nil)
        #expect(draft.isFavorite == false)
        #expect(draft.includeInTotal == true)
        #expect(draft.uniqueID == "")
    }

    @Test("cardType-сеттер синхронизирует cardTypeRaw и наоборот")
    func cardTypeMirrorsRaw() {
        var draft = InlineCardDraft(name: "Card", currency: "RUB")

        draft.cardType = .credit
        #expect(draft.cardTypeRaw == CardType.credit.rawValue)
        #expect(draft.cardType == .credit)

        draft.cardTypeRaw = CardType.debit.rawValue
        #expect(draft.cardType == .debit)
    }

    @Test("priority-сеттер синхронизирует priorityRaw и наоборот")
    func priorityMirrorsRaw() {
        var draft = InlineCardDraft(name: "Card", currency: "RUB")

        draft.priority = .high
        #expect(draft.priorityRaw == CardPriority.high.rawValue)
        #expect(draft.priority == .high)

        draft.priorityRaw = CardPriority.low.rawValue
        #expect(draft.priority == .low)
    }

    @Test("Битый raw откатывается к дефолту, как в легаси-модели")
    func invalidRawFallsBackToDefault() {
        var draft = InlineCardDraft(name: "Card", currency: "RUB")

        draft.cardTypeRaw = "garbage"
        draft.priorityRaw = "garbage"

        #expect(draft.cardType == .debit)
        #expect(draft.priority == .normal)
    }

    @Test("Полный init переносит все поля без потерь")
    func fullInitCarriesAllFields() {
        let draft = InlineCardDraft(
            name: "Кредитка",
            cardNumber: "4242",
            bank: .sberbank,
            cardType: .credit,
            priority: .high,
            currency: "EUR",
            balance: 1500,
            creditLimit: 3000,
            expiryDate: "12/28",
            cardholderName: "IVAN IVANOV",
            cardColor: "#FF0000",
            isFavorite: true,
            includeInTotal: false,
            uniqueID: "fixed-id"
        )

        #expect(draft.name == "Кредитка")
        #expect(draft.cardNumber == "4242")
        #expect(draft.bank == .sberbank)
        #expect(draft.cardType == .credit)
        #expect(draft.priority == .high)
        #expect(draft.currency == "EUR")
        #expect(draft.balance == 1500)
        #expect(draft.creditLimit == 3000)
        #expect(draft.expiryDate == "12/28")
        #expect(draft.cardholderName == "IVAN IVANOV")
        #expect(draft.cardColor == "#FF0000")
        #expect(draft.isFavorite == true)
        #expect(draft.includeInTotal == false)
        #expect(draft.uniqueID == "fixed-id")
    }
}
