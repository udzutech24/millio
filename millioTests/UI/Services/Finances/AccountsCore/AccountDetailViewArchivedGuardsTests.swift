//
//  AccountDetailViewArchivedGuardsTests.swift
//  millioTests
//
//  A4 (ревью round 1, зона «Архивные счета»): «Условия» кредита оставались в меню «···» и
//  открывались с архивного/удалённого кредита — правка условий упиралась в `accountNotWritable`
//  сервиса уже ПОСЛЕ того, как человек начал её вводить. Проверяем сам источник видимости —
//  `AccountDetailView.canEditAccountDetails`/`loanActionSheetItems` — не рендеринг SwiftUI:
//  обе вычисляемые свойства читают только `account.archivedAt`/`deletedAt`, без обращения
//  к @State/окружению, поэтому конструировать `AccountDetailView` напрямую безопасно.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("AccountDetailView: гейт видимости правки на архивном/удалённом счёте")
@MainActor
struct AccountDetailViewArchivedGuardsTests {

    private func makeLoan(context: ModelContext, archived: Bool) throws -> Account {
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(name: "Автокредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000)
        try context.save()
        if archived {
            try service.archiveAccount(account)
        }
        return account
    }

    @Test("canEditAccountDetails: true для живого счёта, false для архивного")
    func canEditAccountDetailsReflectsArchivedState() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let live = try makeLoan(context: ctx, archived: false)
        let archived = try makeLoan(context: ctx, archived: true)

        #expect(AccountDetailView(account: live, modelContext: ctx).canEditAccountDetails)
        #expect(AccountDetailView(account: archived, modelContext: ctx).canEditAccountDetails == false)
    }

    @Test("Меню «···» архивного кредита пустое: «Условия»/«Реквизиты счёта»/«Удалить» скрыты")
    func loanActionSheetItemsHidesTermsAndEditDetailsOnArchivedLoan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let archived = try makeLoan(context: ctx, archived: true)

        let items = AccountDetailView(account: archived, modelContext: ctx).loanActionSheetItems
        let titles = items.map(\.title)

        #expect(titles.contains(L("accounts_core.detail.loan.action.terms")) == false)
        #expect(titles.contains(L("accounts_core.detail.action.edit_details")) == false)
        // Ревью round 2: «Удалить» тоже скрыт — раньше вёл в `archiveAccount()`, который без проверки
        // «уже в архиве» сдвигал `archivedAt` на сегодня (задним числом переписывал историю net worth).
        // Правильный путь для уже архивного счёта — экран «Архив» (restore/softDelete), не эта кнопка.
        #expect(titles.contains(L("accounts_core.detail.action.delete_account")) == false)
        #expect(items.isEmpty, "Архивный/удалённый кредит: меню «···» целиком пустое, тот же паттерн что у generic/вклада/инвест-счёта")
    }

    @Test("Меню «···» живого кредита содержит «Условия» и «Реквизиты счёта»")
    func loanActionSheetItemsShowsTermsAndEditDetailsOnLiveLoan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let live = try makeLoan(context: ctx, archived: false)

        let items = AccountDetailView(account: live, modelContext: ctx).loanActionSheetItems
        let titles = items.map(\.title)

        #expect(titles.contains(L("accounts_core.detail.loan.action.terms")))
        #expect(titles.contains(L("accounts_core.detail.action.edit_details")))
    }

    // Примечание: `handleLoanAction(.terms)` тоже получил defense-in-depth guard (симметричный
    // `canEditAccountDetails`), но его нельзя проверить unit-тестом надёжно — `@State var sheet`
    // сконструированного напрямую (не через рендер SwiftUI) `AccountDetailView` не гарантированно
    // читается обратно после мутации (проверено: тест с этим assert проходил ОДИНАКОВО что с
    // guard'ом, что без него — ложноположительный результат хуже отсутствия теста). Реальная
    // защита пользователя — сам пункт меню скрыт (тест выше); guard в `handleLoanAction` остаётся
    // как defense-in-depth без отдельного покрытия.

    // MARK: - Ревью round 2 (A5): БАГ 6 закрыт кодом (74ee608) для generic/инвест-счетов, но не тестом

    private func makeGenericAccount(context: ModelContext, kind: AccountKind, archived: Bool) throws -> Account {
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(name: "Счёт", kind: kind, currency: "RUB", openingBalance: 0)
        try context.save()
        if archived {
            try service.archiveAccount(account)
        }
        return account
    }

    /// Grep по `genericOverflowItems`/`overflowItems` в millioTests до этого теста не находил ничего —
    /// пункты меню «···» generic-счетов (карта/наличные/банк) не были покрыты НИ ОДНИМ тестом, хотя
    /// сам гейт (`guard account.archivedAt == nil, account.deletedAt == nil else { return [] }`)
    /// в коде уже есть с 74ee608. `overflowItems` — то же свойство, что определяет видимость toolbar-
    /// фолбэка «···» в `AccountDetailView.swift:241` (`!isActionsRowVisible && !overflowItems.isEmpty`).
    @Test("Меню «···» архивного generic-счёта (карта/наличные/банк) пустое")
    func genericOverflowItemsIsEmptyOnArchivedAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let archived = try makeGenericAccount(context: ctx, kind: .cash, archived: true)

        let view = AccountDetailView(account: archived, modelContext: ctx)
        #expect(view.genericOverflowItems.isEmpty)
        #expect(view.overflowItems.isEmpty, "От этого свойства зависит видимость toolbar-фолбэка «···»")
    }

    @Test("Меню «···» живого generic-счёта не пустое (регресс-guard: гейт не должен схлопывать и живой счёт)")
    func genericOverflowItemsIsNotEmptyOnLiveAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let live = try makeGenericAccount(context: ctx, kind: .bankAccount, archived: false)

        let view = AccountDetailView(account: live, modelContext: ctx)
        #expect(view.genericOverflowItems.isEmpty == false)
    }

    @Test("Меню «···» архивного инвест-счёта (marketInvestment) пустое")
    func marketOverflowItemsIsEmptyOnArchivedAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let archived = try makeGenericAccount(context: ctx, kind: .marketInvestment, archived: true)

        let view = AccountDetailView(account: archived, modelContext: ctx)
        #expect(view.overflowItems.isEmpty)
    }

    @Test("Меню «···» живого инвест-счёта не пустое (регресс-guard)")
    func marketOverflowItemsIsNotEmptyOnLiveAccount() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let live = try makeGenericAccount(context: ctx, kind: .marketInvestment, archived: false)

        let view = AccountDetailView(account: live, modelContext: ctx)
        #expect(view.overflowItems.isEmpty == false)
    }
}
