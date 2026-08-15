//
//  CardCatalogTests.swift
//  millioTests
//

import Foundation
import SwiftData
import Testing
@testable import millio

struct CardCatalogTests {
    @MainActor
    @Test("Legacy importer resolves stable ID before mutable display fields")
    func importerUsesStableIDFirst() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let existing = Card(name: "Old name", cardNumber: "1111", cardType: .debit, currency: "RUB", balance: 10)
        existing.uniqueID = "stable-card-id"
        context.insert(existing)
        try context.save()

        try CardImporter.import(from: [
            "name": "Renamed", "cardNumber": "2222", "bankRaw": Bank.other.rawValue,
            "cardTypeRaw": CardType.debit.rawValue, "currency": "USD", "balance": 20.0,
            "createdAt": 1.0, "updatedAt": 2.0, "cardUniqueID": "stable-card-id"
        ], context: context)

        let rows = try context.fetch(FetchDescriptor<Card>())
        #expect(rows.count == 1)
        #expect(rows.first?.uniqueID == "stable-card-id")
        #expect(rows.first?.balance == 20)
    }

    @MainActor
    @Test("Ordinary fetch deduplicates its read model without mutating persistent rows")
    func fetchAllIsPureForDuplicateRows() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let sharedID = "CARD-DESTRUCTIVE-READ"

        let stale = Card(name: "Old", cardNumber: "1111", cardType: .debit, currency: "RUB", balance: 100)
        stale.uniqueID = sharedID
        stale.updatedAt = Date(timeIntervalSince1970: 1)
        let fresh = Card(name: "New", cardNumber: "2222", cardType: .debit, currency: "RUB", balance: 200)
        fresh.uniqueID = sharedID
        fresh.updatedAt = Date(timeIntervalSince1970: 2)
        context.insert(stale)
        context.insert(fresh)
        try context.save()

        let result = CardCatalog.fetchAll(in: context)
        let persisted = try context.fetch(FetchDescriptor<Card>())

        #expect(result.count == 1)
        #expect(persisted.count == 2)
        #expect(context.hasChanges == false)
    }

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
