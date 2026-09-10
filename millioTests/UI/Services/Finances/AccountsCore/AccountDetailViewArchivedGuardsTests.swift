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

    @Test("Меню «···» архивного кредита не содержит «Условия»/«Реквизиты счёта»")
    func loanActionSheetItemsHidesTermsAndEditDetailsOnArchivedLoan() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let archived = try makeLoan(context: ctx, archived: true)

        let items = AccountDetailView(account: archived, modelContext: ctx).loanActionSheetItems
        let titles = items.map(\.title)

        #expect(titles.contains(L("accounts_core.detail.loan.action.terms")) == false)
        #expect(titles.contains(L("accounts_core.detail.action.edit_details")) == false)
        // «Удалить» остаётся — архив/удаление счёта не запрещает повторную архивацию/удаление.
        #expect(titles.contains(L("accounts_core.detail.action.delete_account")))
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
}
