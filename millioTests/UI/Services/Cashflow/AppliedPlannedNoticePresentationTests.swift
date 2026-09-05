//
//  AppliedPlannedNoticePresentationTests.swift
//  millioTests
//
//  Гейт фазы 2 «уведомление о применённых плановых операциях» — четыре сценария владельца:
//  (а) применение при активном приложении → сводка показывается;
//  (б) применилось и свернул/развернул → сводка ровно один раз, третий вход пуст;
//  (в) при блокировке (Face ID) сводка ждёт снятия блокировки и не пропадает;
//  (г) лист выписки и сводка в один заход не конфликтуют — сводка ждёт своей очереди.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@MainActor
@Suite("AppliedPlannedNoticePresentation — гейт показа сводки")
struct AppliedPlannedNoticePresentationTests {

    // MARK: - Harness

    private func makeStore() -> AppliedPlannedNoticeStore {
        let suiteName = "tests.cashflow.appliedPlannedNotice.presentation.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AppliedPlannedNoticeStore(defaults: defaults, scopeIdentifier: "millio_user_owner")
    }

    private func appliedEntry(amount: Decimal = Decimal(string: "-45000")!) -> AppliedPlannedEntry {
        AppliedPlannedEntry(
            title: "Аренда",
            accountName: "Основной счёт",
            amount: amount,
            currencyCode: "RUB",
            appliedAt: Date(timeIntervalSince1970: 1_757_000_000),
            kind: .scheduled
        )
    }

    /// Приложение активно, экран свободен, ничего не блокирует показ.
    private func idleReadiness(
        isAppLocked: Bool = false,
        isStoreReady: Bool = true,
        isModalBusy: Bool = false,
        hasPendingStatement: Bool = false,
        isAlreadyPresenting: Bool = false
    ) -> AppliedPlannedNoticePresentation.Readiness {
        AppliedPlannedNoticePresentation.Readiness(
            isAppLocked: isAppLocked,
            isStoreReady: isStoreReady,
            isModalBusy: isModalBusy,
            hasPendingStatement: hasPendingStatement,
            isAlreadyPresenting: isAlreadyPresenting
        )
    }

    // MARK: - (а) применение при активном приложении

    @Test("Применение при активном приложении показывает сводку сразу")
    func appliedWhileActiveShowsNotice() {
        let store = makeStore()
        store.append(appliedEntry())

        let item = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())

        #expect(item?.digest.totalCount == 1)
    }

    @Test("Пустой журнал не показывает ничего")
    func emptyJournalShowsNothing() {
        let store = makeStore()

        #expect(
            AppliedPlannedNoticePresentation.decide(
                hasPendingNotice: store.hasPending,
                readiness: idleReadiness()
            ) == .nothing
        )
        #expect(AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness()) == nil)
    }

    // MARK: - (б) свернул/развернул — сводка ровно один раз

    @Test("Сводка показывается один раз: второй и третий заход пусты")
    func noticeShownOnlyOnce() {
        let store = makeStore()
        store.append(appliedEntry())

        let first = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())
        let second = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())
        let third = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())

        #expect(first != nil)
        #expect(second == nil)
        #expect(third == nil)
        #expect(store.hasPending == false)
    }

    @Test("Пока сводка на экране, вторая не подставляется")
    func alreadyPresentingSuppressesSecondNotice() {
        let store = makeStore()
        store.append(appliedEntry())

        let decision = AppliedPlannedNoticePresentation.decide(
            hasPendingNotice: store.hasPending,
            readiness: idleReadiness(isAlreadyPresenting: true)
        )

        #expect(decision == .nothing)
        #expect(AppliedPlannedNoticePresentation.makeItem(
            store: store,
            readiness: idleReadiness(isAlreadyPresenting: true)
        ) == nil)
        // Журнал не тронут: сводка покажется, когда экран освободится.
        #expect(store.hasPending == true)
    }

    // MARK: - (в) блокировка

    @Test("При блокировке сводка ждёт и не теряется, после снятия — показывается")
    func lockedWaitsAndKeepsJournal() {
        let store = makeStore()
        store.append(appliedEntry())

        let locked = AppliedPlannedNoticePresentation.decide(
            hasPendingNotice: store.hasPending,
            readiness: idleReadiness(isAppLocked: true)
        )
        #expect(locked == .wait)
        #expect(AppliedPlannedNoticePresentation.makeItem(
            store: store,
            readiness: idleReadiness(isAppLocked: true)
        ) == nil)
        #expect(store.hasPending == true)

        let afterUnlock = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())
        #expect(afterUnlock?.digest.totalCount == 1)
    }

    @Test("Неготовый стор и занятый модалом экран тоже дают ожидание")
    func storeUnavailableAndModalBusyWait() {
        let store = makeStore()
        store.append(appliedEntry())

        #expect(
            AppliedPlannedNoticePresentation.decide(
                hasPendingNotice: true,
                readiness: idleReadiness(isStoreReady: false)
            ) == .wait
        )
        #expect(
            AppliedPlannedNoticePresentation.decide(
                hasPendingNotice: true,
                readiness: idleReadiness(isModalBusy: true)
            ) == .wait
        )
        #expect(store.hasPending == true)
    }

    // MARK: - (г) очередь с листом выписки

    @Test("Лист выписки приоритетнее: сводка ждёт его закрытия")
    func statementSheetGoesFirst() {
        let store = makeStore()
        store.append(appliedEntry())

        let whileStatement = AppliedPlannedNoticePresentation.makeItem(
            store: store,
            readiness: idleReadiness(hasPendingStatement: true)
        )
        #expect(whileStatement == nil)
        #expect(store.hasPending == true)

        let afterStatement = AppliedPlannedNoticePresentation.makeItem(store: store, readiness: idleReadiness())
        #expect(afterStatement?.digest.totalCount == 1)
    }

    // MARK: - Пустой журнал при любой занятости

    @Test("Без непоказанного показывать нечего даже при блокировке")
    func noticeAbsentBeatsWait() {
        #expect(
            AppliedPlannedNoticePresentation.decide(
                hasPendingNotice: false,
                readiness: idleReadiness(isAppLocked: true)
            ) == .nothing
        )
    }

    // MARK: - Триггер из цикла применения

    @Test("VM просит показ только когда в журнале есть непоказанное")
    func viewModelNotifiesOnlyWhenJournalHasEntries() throws {
        let suiteName = "tests.cashflow.appliedPlannedNotice.vm.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let viewModel = CashflowViewModel(modelContext: container.mainContext, defaults: defaults)

        var requests = 0
        viewModel.onPlannedOperationsApplied = { requests += 1 }

        // Цикл отработал вхолостую — просить показ не о чем.
        viewModel.notifyAppliedPlannedNoticeIfPending()
        #expect(requests == 0)

        viewModel.appliedPlannedNoticeStore.append(appliedEntry())
        viewModel.notifyAppliedPlannedNoticeIfPending()
        #expect(requests == 1)
    }
}
