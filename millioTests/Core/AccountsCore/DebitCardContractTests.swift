import Foundation
import Testing
@testable import millio

@Suite("Debit-card pure contract")
@MainActor
struct DebitCardContractTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func account(currency: String = "RUB", product: AccountProductType = .debitCard) -> Account {
        let value = Account(name: "Debit", kind: .debitCard, productType: product, currency: currency)
        value.cardMeta = CardMeta()
        return value
    }

    private func event(_ type: AccountEventType, _ amount: Decimal, date: Date? = nil) -> AccountEvent {
        AccountEvent(date: date ?? self.date, createdAt: date ?? self.date, type: type, amount: amount)
    }

    @Test("Replay equation and effective-date boundary are deterministic")
    func replayAndEffectiveDate() throws {
        let card = account()
        let future = date.addingTimeInterval(100)
        let events = [event(.expense, 20), event(.openingBalance, 100), event(.fee, 5), event(.income, 10), event(.income, 999, date: future)]
        #expect(try DebitCardContract.balance(account: card, events: events, on: date) == 85)
        #expect(try DebitCardContract.balance(account: card, events: events.reversed(), on: date) == 85)
        #expect(try DebitCardContract.balance(account: card, events: events, on: future) == 1084)
    }

    @Test("ISO minor units use Decimal bankers rounding")
    func currencyRounding() {
        #expect(DebitCurrencyPolicy.round(Decimal(string: "1.005")!, currency: "USD") == Decimal(string: "1.00"))
        #expect(DebitCurrencyPolicy.round(Decimal(string: "1.6")!, currency: "JPY") == 2)
        #expect(DebitCurrencyPolicy.round(Decimal(string: "1.2345")!, currency: "KWD") == Decimal(string: "1.234"))
    }

    @Test("Magnitude, overdraft, archive, product and adjustment reason are rejected")
    func validation() throws {
        let card = account()
        let events = [event(.openingBalance, 100)]
        #expect(throws: DebitCardContractError.invalidAmount) { try DebitCardContract.validate(account: card, events: events, kind: .expense, amount: 0, on: date) }
        #expect(throws: DebitCardContractError.invalidAmount) { try DebitCardContract.validate(account: card, events: events, kind: .income, amount: -1, on: date) }
        #expect(throws: DebitCardContractError.insufficientFunds) { try DebitCardContract.validate(account: card, events: events, kind: .expense, amount: 101, on: date) }
        #expect(throws: DebitCardContractError.invalidAdjustmentReason) { try DebitCardContract.validate(account: card, events: events, kind: .adjustment(reason: " "), amount: 1, on: date) }
        card.archivedAt = date
        #expect(throws: DebitCardContractError.archivedAccount) { try DebitCardContract.validate(account: card, events: events, kind: .income, amount: 1, on: date) }
        #expect(throws: DebitCardContractError.invalidProduct) { try DebitCardContract.balance(account: account(product: .creditCard), events: events, on: date) }
    }

    @Test("Typed snapshot separates actual, conversion, totals and lifecycle")
    func typedSnapshot() throws {
        let card = account()
        card.cardMeta = nil
        card.includeInTotal = false
        let events = [event(.openingBalance, 100)]
        let active = try #require(DebitCardContract.snapshot(
            account: card, events: events, on: date,
            converted: .provisional(Decimal(string: "1.25")!, "USD")
        ))
        #expect(active.actualBalance == 100)
        #expect(active.converted == .provisional(Decimal(string: "1.25")!, "USD"))
        #expect(!active.participatesInTotal)
        #expect(active.canWrite)
        #expect(active.incompleteReason == nil)

        card.archivedAt = date
        let archived = try #require(DebitCardContract.snapshot(account: card, events: events, on: date))
        #expect(archived.lifecycle == .archived)
        #expect(!archived.canWrite)
    }
}
