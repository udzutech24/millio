//
//  LoanTermsEditSheetArchivedGuardTests.swift
//  millioTests
//
//  A4 (ревью round 1, зона «Архивные счета»): `save()` писал `LoanContractStore.upsert` НАПРЯМУЮ,
//  в обход `AccountsCoreService.requireWritable` (тот охраняет только `AccountEvent`, не
//  `LoanContract`). На архивном кредите это било по одному из двух путей:
//  — правка ставки/срока без суммы (`principalChanged == false`) сохранялась голым
//    `modelContext.save()` без ЕДИНОЙ проверки писуемости счёта;
//  — правка суммы (`principalChanged == true`) доходила до `LoanPrincipalCorrection.alignOutstanding`
//    → `recordEvent` → `requireWritable`, бросала, но уже применённая мутация `LoanContract.principal`
//    оставалась «грязной» в контексте без отката.
//  `save()` тестируется напрямую (не `private`, см. комментарий в файле) — единственный надёжный
//  способ проверить именно то поведение, которое видит человек, а не переизобретённую копию логики.
//

import Foundation
import SwiftData
import Testing
@testable import millio

@Suite("LoanTermsEditSheet: архивный/удалённый кредит блокирует save()")
@MainActor
struct LoanTermsEditSheetArchivedGuardTests {

    /// Живой договор с валидными условиями (принят `LoanTermsDraft.terms` — без него `save()`
    /// вышел бы на первом guard'е формы, ещё до архивного барьера, и тест ничего не доказал бы).
    private func makeLoanWithContract(context: ModelContext, archived: Bool) throws -> (Account, LoanContract) {
        let service = AccountsCoreService(modelContext: context)
        let account = try service.createAccount(name: "Автокредит", kind: .loan, currency: "RUB", openingBalance: 1_200_000)
        try context.save()

        let store = LoanContractStore(context: context)
        try store.upsert(accountID: account.id) { contract in
            contract.principal = 1_200_000
            contract.annualRatePercent = 12
            contract.termPeriods = 24
            contract.firstPaymentDate = Calendar.current.date(byAdding: .month, value: 1, to: Date())!
        }
        try context.save()

        if archived {
            try service.archiveAccount(account)
        }
        let contract = try #require(try store.contract(for: account.id))
        return (account, contract)
    }

    @Test("save() на архивном кредите не трогает LoanContract и не зовёт onSaved")
    func saveOnArchivedLoanDoesNotMutateContract() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let (account, contract) = try makeLoanWithContract(context: ctx, archived: true)
        let principalBefore = contract.principal

        var onSavedCalled = false
        let sheet = LoanTermsEditSheet(account: account, modelContext: ctx, contract: contract, onSaved: { onSavedCalled = true })
        sheet.save()

        #expect(onSavedCalled == false, "Правка не должна была пройти дальше guard'а")
        let reloaded = try #require(try LoanContractStore(context: ctx).contract(for: account.id))
        #expect(reloaded.principal == principalBefore, "Сумма договора не должна была измениться")
    }

    @Test("save() на живом кредите проходит и трогает LoanContract (контроль: guard не блокирует нормальный путь)")
    func saveOnLiveLoanStillWorks() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let (account, contract) = try makeLoanWithContract(context: ctx, archived: false)
        _ = contract

        var onSavedCalled = false
        let sheet = LoanTermsEditSheet(account: account, modelContext: ctx, contract: contract, onSaved: { onSavedCalled = true })
        sheet.save()

        #expect(onSavedCalled, "Guard не должен блокировать правку живого кредита")
    }
}
