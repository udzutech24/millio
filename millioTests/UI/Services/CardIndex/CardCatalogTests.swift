//
//  CardCatalogTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

struct CardCatalogTests {
    @Test("CardSnapshot для кредитки даёт единые available/debt/net worth значения")
    func creditCardSnapshotUsesSharedSemantics() {
        let card = Card(
            name: "Credit",
            cardNumber: "1111",
            bank: .tinkoff,
            cardType: .credit,
            currency: "RUB",
            balance: 213_641,
            creditLimit: 560_000
        )

        let snapshot = CardSnapshotFactory.make(from: card)

        #expect(snapshot.availableAmount == 213_641)
        #expect(snapshot.debtAmount == 346_359)
        #expect(snapshot.netWorthAmount == -346_359)
    }

    @Test("CardCatalog dedupe выбирает самую новую запись карты")
    func dedupeKeepsNewestCardVersion() {
        let sharedID = "CARD-DUPLICATE-ID"

        let stale = Card(
            name: "Old",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 100
        )
        stale.uniqueID = sharedID
        stale.updatedAt = Date(timeIntervalSince1970: 1)

        let fresh = Card(
            name: "New",
            cardNumber: "1111",
            bank: .sberbank,
            cardType: .debit,
            currency: "RUB",
            balance: 250
        )
        fresh.uniqueID = sharedID
        fresh.updatedAt = Date(timeIntervalSince1970: 2)

        let deduped = CardCatalog.deduped([stale, fresh])

        #expect(deduped.count == 1)
        #expect(deduped.first?.name == "New")
        #expect(deduped.first?.balance == 250)
    }
}
