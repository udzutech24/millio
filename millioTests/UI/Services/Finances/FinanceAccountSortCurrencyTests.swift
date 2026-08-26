import Foundation
import SwiftData
import Testing
@testable import millio

/// Регрессия: сортировка списка счетов по сумме сравнивала СЫРЫЕ балансы в валюте счёта.
/// 1 000 USD (≈90 000 ₽) оказывались ниже 5 000 ₽ просто потому, что 1000 < 5000.
@Suite(.serialized)
@MainActor
struct FinanceAccountSortCurrencyTests {

    // `loadAccounts` планирует fire-and-forget Task, трогающий стор после возврата из теста.
    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        UserDefaults.standard.set("RUB", forKey: "primaryCurrencyCode")
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext, rates: [String: Double]?) -> FinanceViewModel {
        let service = MockCurrencyRateService()
        service.usdBasedRates = rates
        let vm = FinanceViewModel(modelContext: ctx, currencyService: service, skipInitialLoad: true)
        vm.state.displayCurrency = "RUB"
        Self.retained.append(vm)
        Self.retained.append(service)
        return vm
    }

    /// Два счёта без группы: 1 000 USD и 5 000 RUB при курсе 1 USD = 90 RUB.
    private func seedMixedCurrencyAccounts(_ ctx: ModelContext) throws {
        let service = AccountsCoreService(modelContext: ctx)
        _ = try service.createAccount(
            name: "Долларовый", kind: .debitCard, currency: "USD", openingBalance: 1_000, group: nil
        )
        _ = try service.createAccount(
            name: "Рублёвый", kind: .debitCard, currency: "RUB", openingBalance: 5_000, group: nil
        )
        try ctx.save()
    }

    @Test("По убыванию суммы валютный счёт идёт выше рублёвого с меньшим эквивалентом")
    func amountDescendingConvertsToDisplayCurrency() throws {
        let ctx = try makeContext()
        try seedMixedCurrencyAccounts(ctx)
        let vm = makeViewModel(ctx, rates: ["RUB": 90])
        vm.handle(.setAccountSortMode(.amountDescending))

        #expect(vm.ungroupedAccounts().map(\.name) == ["Долларовый", "Рублёвый"])
    }

    @Test("По возрастанию суммы порядок зеркальный")
    func amountAscendingConvertsToDisplayCurrency() throws {
        let ctx = try makeContext()
        try seedMixedCurrencyAccounts(ctx)
        let vm = makeViewModel(ctx, rates: ["RUB": 90])
        vm.handle(.setAccountSortMode(.amountAscending))

        #expect(vm.ungroupedAccounts().map(\.name) == ["Рублёвый", "Долларовый"])
    }

    /// Курсов нет (пустой offline-кэш) — счета не должны исчезать или падать в 0;
    /// сравниваются по сырым значениям, как до фикса.
    @Test("Без снимка курсов сортировка деградирует к сырым суммам, но не теряет счета")
    func missingRatesFallsBackToRawAmounts() throws {
        let ctx = try makeContext()
        try seedMixedCurrencyAccounts(ctx)
        let vm = makeViewModel(ctx, rates: nil)
        vm.handle(.setAccountSortMode(.amountDescending))

        #expect(Set(vm.ungroupedAccounts().map(\.name)) == ["Долларовый", "Рублёвый"])
    }
}
