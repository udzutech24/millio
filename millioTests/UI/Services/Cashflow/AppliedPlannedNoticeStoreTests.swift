//
//  AppliedPlannedNoticeStoreTests.swift
//  millioTests
//
//  Гейт фазы 0 «уведомление о применённых плановых операциях»:
//  1) append → takeDigest отдаёт данные, повторный вызов пуст (сводка не показывается дважды);
//  2) два scope не видят записей друг друга (гость не гасит сводку владельца);
//  3) потолок деталей не искажает агрегат — 300 применений остаются 300;
//  4) валюты не сливаются в одну цифру, итог по каждой — нетто.
//

import Foundation
import Testing
@testable import millio

@MainActor
@Suite("AppliedPlannedNoticeStore — журнал непоказанных применений")
struct AppliedPlannedNoticeStoreTests {

    private static let ownerScope = "millio_user_owner"
    private static let guestScope = "millio_guest"

    // MARK: - Harness

    private func makeDefaults() -> UserDefaults {
        let suiteName = "tests.cashflow.appliedPlannedNotice.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func entry(
        title: String = "Аренда",
        accountName: String = "Основной счёт",
        amount: Decimal,
        currencyCode: String = "RUB",
        kind: AppliedPlannedEntry.Kind = .scheduled
    ) -> AppliedPlannedEntry {
        AppliedPlannedEntry(
            title: title,
            accountName: accountName,
            amount: amount,
            currencyCode: currencyCode,
            appliedAt: Date(timeIntervalSince1970: 1_757_000_000),
            kind: kind
        )
    }

    // MARK: - 1. append → takeDigest → пусто

    @Test("append кладёт записи, takeDigest отдаёт их и очищает журнал")
    func appendThenTakeDigestClearsJournal() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)

        #expect(store.hasPending == false)
        #expect(store.takeDigest() == nil)

        let salary = entry(title: "Зарплата", amount: Decimal(string: "120000")!, kind: .recurring)
        let rent = entry(title: "Аренда", amount: Decimal(string: "-45000")!)
        store.append(salary)
        store.append(rent)

        #expect(store.hasPending)

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 2)
        #expect(digest.incomeCount == 1)
        #expect(digest.expenseCount == 1)
        #expect(digest.details.map(\.id) == [salary.id, rent.id])
        #expect(digest.details.first?.kind == .recurring)
        #expect(digest.truncatedCount == 0)
        #expect(digest.totalsByCurrency["RUB"] == Decimal(string: "75000")!)

        #expect(store.hasPending == false)
        #expect(store.takeDigest() == nil)

        // Очистка должна быть записана в UserDefaults, а не жить в памяти экземпляра:
        // показ сводки и следующий запуск — это разные экземпляры стора.
        let reopened = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        #expect(reopened.hasPending == false)
        #expect(reopened.takeDigest() == nil)
    }

    // MARK: - 2. Изоляция по scope

    @Test("Два scope в одних UserDefaults не видят записей друг друга")
    func scopesAreIsolated() throws {
        let defaults = makeDefaults()
        let owner = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        let guest = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.guestScope)

        owner.append(entry(title: "Аренда владельца", amount: Decimal(string: "-45000")!))

        #expect(owner.hasPending)
        #expect(guest.hasPending == false)
        #expect(guest.takeDigest() == nil)

        guest.append(entry(title: "Гостевой доход", amount: Decimal(string: "500")!))
        guest.append(entry(title: "Гостевой расход", amount: Decimal(string: "-100")!))

        // takeDigest гостя не должен гасить журнал владельца.
        let guestDigest = try #require(guest.takeDigest())
        #expect(guestDigest.totalCount == 2)

        let ownerDigest = try #require(owner.takeDigest())
        #expect(ownerDigest.totalCount == 1)
        #expect(ownerDigest.details.first?.title == "Аренда владельца")
        #expect(ownerDigest.totalsByCurrency["RUB"] == Decimal(string: "-45000")!)
    }

    // MARK: - 3. Потолок деталей не искажает агрегат

    @Test("300 применений: счётчик и суммы точные, деталей ровно 50")
    func detailsCapDoesNotDistortAggregate() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)

        let unitAmount = Decimal(string: "10.55")!
        for index in 0..<300 {
            store.append(entry(title: "Операция \(index)", amount: unitAmount, kind: .recurring))
        }

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 300)
        #expect(digest.incomeCount == 300)
        #expect(digest.expenseCount == 0)
        #expect(digest.details.count == AppliedPlannedDigest.detailsCap)
        #expect(digest.details.count == 50)
        #expect(digest.truncatedCount == 250)
        // 300 × 10.55 = 3165 — суммируется весь поток, а не только сохранённые детали.
        #expect(digest.totalsByCurrency["RUB"] == Decimal(string: "3165")!)
        #expect(digest.details.first?.title == "Операция 0")
        #expect(digest.details.last?.title == "Операция 49")
    }

    // MARK: - 4. Валюты и нетто

    @Test("totalsByCurrency разделяет валюты и считает нетто")
    func totalsAreNetPerCurrency() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)

        store.append(entry(title: "Зарплата", amount: Decimal(string: "1000")!, currencyCode: "RUB"))
        store.append(entry(title: "Аренда", amount: Decimal(string: "-250.50")!, currencyCode: "RUB"))
        store.append(entry(
            title: "Проценты по вкладу",
            amount: Decimal(string: "30.25")!,
            currencyCode: "USD",
            kind: .depositInterest
        ))
        store.append(entry(title: "Подписка", amount: Decimal(string: "-100")!, currencyCode: "USD"))

        let digest = try #require(store.takeDigest())
        #expect(digest.totalCount == 4)
        #expect(digest.incomeCount == 2)
        #expect(digest.expenseCount == 2)
        #expect(digest.totalsByCurrency.count == 2)
        #expect(digest.totalsByCurrency["RUB"] == Decimal(string: "749.50")!)
        #expect(digest.totalsByCurrency["USD"] == Decimal(string: "-69.75")!)
        // Конвертации нет — валюты не должны схлопываться в одну строку.
        #expect(digest.totalsByCurrency["EUR"] == nil)
    }
}
