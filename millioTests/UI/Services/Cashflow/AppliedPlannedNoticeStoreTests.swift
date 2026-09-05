//
//  AppliedPlannedNoticeStoreTests.swift
//  millioTests
//
//  Гейт фазы 0 «уведомление о применённых плановых операциях»:
//  1) append → beginPresentation отдаёт данные, finishPresentation гасит журнал;
//  2) два scope не видят записей друг друга (гость не гасит сводку владельца);
//  3) потолок деталей не искажает агрегат — 300 применений остаются 300;
//  4) валюты не сливаются в одну цифру, итог по каждой — нетто.
//  5) (Ф4) журнал переживает перезапуск, пока лист открыт, — очистка только на закрытии.
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

    // MARK: - 1. append → beginPresentation → finishPresentation → пусто

    @Test("append кладёт записи, beginPresentation отдаёт их, finishPresentation очищает журнал")
    func appendThenFinishPresentationClearsJournal() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)

        #expect(store.hasPending == false)
        #expect(store.beginPresentation() == nil)

        let salary = entry(title: "Зарплата", amount: Decimal(string: "120000")!, kind: .recurring)
        let rent = entry(title: "Аренда", amount: Decimal(string: "-45000")!)
        store.append(salary)
        store.append(rent)

        #expect(store.hasPending)

        let digest = try #require(store.beginPresentation())
        #expect(digest.totalCount == 2)
        #expect(digest.incomeCount == 1)
        #expect(digest.expenseCount == 1)
        #expect(digest.details.map(\.id) == [salary.id, rent.id])
        #expect(digest.details.first?.kind == .recurring)
        #expect(digest.truncatedCount == 0)
        #expect(digest.totalsByCurrency["RUB"] == Decimal(string: "75000")!)

        // Показ журнал не гасит: пользователь ещё не закрыл лист.
        #expect(store.hasPending)

        store.finishPresentation(digest)
        #expect(store.hasPending == false)
        #expect(store.beginPresentation() == nil)

        // Очистка должна быть записана в UserDefaults, а не жить в памяти экземпляра:
        // показ сводки и следующий запуск — это разные экземпляры стора.
        let reopened = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        #expect(reopened.hasPending == false)
        #expect(reopened.beginPresentation() == nil)
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
        #expect(guest.beginPresentation() == nil)

        guest.append(entry(title: "Гостевой доход", amount: Decimal(string: "500")!))
        guest.append(entry(title: "Гостевой расход", amount: Decimal(string: "-100")!))

        // Показ и закрытие сводки гостя не должны гасить журнал владельца.
        let guestDigest = try #require(guest.beginPresentation())
        #expect(guestDigest.totalCount == 2)
        guest.finishPresentation(guestDigest)
        #expect(guest.hasPending == false)

        let ownerDigest = try #require(owner.beginPresentation())
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

        let digest = try #require(store.beginPresentation())
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

        let digest = try #require(store.beginPresentation())
        #expect(digest.totalCount == 4)
        #expect(digest.incomeCount == 2)
        #expect(digest.expenseCount == 2)
        #expect(digest.totalsByCurrency.count == 2)
        #expect(digest.totalsByCurrency["RUB"] == Decimal(string: "749.50")!)
        #expect(digest.totalsByCurrency["USD"] == Decimal(string: "-69.75")!)
        // Конвертации нет — валюты не должны схлопываться в одну строку.
        #expect(digest.totalsByCurrency["EUR"] == nil)
    }

    // MARK: - 5. Журнал переживает перезапуск, пока лист открыт

    @Test("Убитое с открытым листом приложение не теряет сводку; чистит её только закрытие")
    func journalSurvivesRelaunchWhileSheetIsOpen() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        store.append(entry(title: "Аренда", amount: Decimal(string: "-45000")!))

        // Лист показан.
        let shown = try #require(store.beginPresentation())
        #expect(shown.totalCount == 1)

        // Пользователь убил приложение, не закрыв лист: новый запуск = новый экземпляр стора
        // на тех же UserDefaults. Сводка обязана быть на месте.
        let afterRelaunch = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        #expect(afterRelaunch.hasPending)
        let reshown = try #require(afterRelaunch.beginPresentation())
        #expect(reshown == shown)

        // Теперь лист закрыт — и только теперь журнал пуст, в том числе для следующего запуска.
        afterRelaunch.finishPresentation(reshown)
        #expect(afterRelaunch.hasPending == false)
        let nextLaunch = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        #expect(nextLaunch.beginPresentation() == nil)
    }

    // MARK: - 6. Дописанное во время показа не теряется

    @Test("Применение во время открытого листа не стирается его закрытием")
    func entriesAppendedWhilePresentingSurviveDismiss() throws {
        let defaults = makeDefaults()
        let store = AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: Self.ownerScope)
        store.append(entry(title: "Аренда", amount: Decimal(string: "-45000")!))

        let shown = try #require(store.beginPresentation())

        // Полночь перевела повторяющуюся операцию, пока лист был на экране.
        store.append(entry(title: "Подписка", amount: Decimal(string: "-299")!, kind: .recurring))

        // Закрытие гасит только показанное; раз журнал изменился — он остаётся целиком,
        // и пользователь увидит обе записи на следующем показе.
        store.finishPresentation(shown)
        let next = try #require(store.beginPresentation())
        #expect(next.totalCount == 2)
        #expect(next.details.map(\.title) == ["Аренда", "Подписка"])
    }
}
