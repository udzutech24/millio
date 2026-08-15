import Foundation
import SwiftData
import Testing
@testable import millio

/// Гейт 5c.7.6.2 — проверка проводки: `FinanceViewModel.state.groupTotalsPrimaryCurrency`/
/// `.ungroupedTotal` реально заполняются мутацией стора и держат инвариант «подытоги секций
/// Активы/Обязательства == тотал шапки» на CORE-STORE фикстуре (актив + обязательство + Ungrouped,
/// БЕЗ легаси-хвоста). Честный mixed-store случай (легаси-хвост есть) — отдельный тест ниже,
/// документирующий ОЖИДАЕМОЕ расхождение (инвариант 9 §2.1), а не "==" из этого теста.
@Suite(.serialized)
@MainActor
struct FinanceAccountsSectionsIntegrationTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func waitForAsyncStatePropagation(
        until condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<100 {
            await Task.yield()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("Cold initial load: валютная группа публикует native- и primary-тоталы")
    func coldInitialLoadPublishesPrimaryCurrencyGroupTotal() async throws {
        let defaults = UserDefaults.standard
        let previousPrimaryCurrency = defaults.string(forKey: "primaryCurrencyCode")
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defer {
            if let previousPrimaryCurrency {
                defaults.set(previousPrimaryCurrency, forKey: "primaryCurrencyCode")
            } else {
                defaults.removeObject(forKey: "primaryCurrencyCode")
            }
        }

        let ctx = try makeContext()
        let group = AccountGroup(name: "Foreign accounts", displayCurrency: "USD")
        ctx.insert(group)

        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "USD cash",
            kind: .cash,
            currency: "USD",
            openingBalance: 100,
            group: group,
            date: Date().addingTimeInterval(-86_400)
        )
        try ctx.save()

        let rates = MockCurrencyRateService()
        rates.setRate(from: "USD", to: "RUB", rate: 90)
        let viewModel = FinanceViewModel(
            modelContext: ctx,
            currencyService: rates,
            skipInitialLoad: false
        )

        let propagated = await waitForAsyncStatePropagation {
            viewModel.state.groupTotals[group.groupUniqueID] != nil
                && viewModel.state.groupTotalsPrimaryCurrency[group.groupUniqueID] != nil
        }
        #expect(
            propagated,
            "Initial load обязан публиковать primary-тотал без ожидания row task, refresh или FinanceEvent"
        )
        #expect(abs((viewModel.state.groupTotals[group.groupUniqueID] ?? 0) - 100) < 0.01)
        #expect(abs((viewModel.state.groupTotalsPrimaryCurrency[group.groupUniqueID] ?? 0) - 9_000) < 0.01)
    }

    @Test("Core-store: подытоги секций сходятся с тотал шапки на активе+обязательстве+Ungrouped")
    func sectionSubtotalsMatchHeaderTotal() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-30 * 86_400)

        let coreGroupA = AccountGroup(name: "Активы группа")
        let coreGroupB = AccountGroup(name: "Кредит группа")
        ctx.insert(coreGroupA)
        ctx.insert(coreGroupB)

        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 500_000,
            group: coreGroupA, date: createdAt
        )
        _ = try accountsService.createAccount(
            name: "Кредит", kind: .loan, currency: "RUB", openingBalance: 300_000,
            group: coreGroupB, date: createdAt
        )
        _ = try accountsService.createAccount(
            name: "Без группы", kind: .cash, currency: "RUB", openingBalance: 150_000,
            group: nil, date: createdAt
        )
        try ctx.save()

        let viewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        // `refreshGroupTotalsAndAmounts` заполняет `groupTotalsPrimaryCurrency` В ЦИКЛЕ, а
        // `state.totalAmount` — ПОСЛЕДНИМ шагом той же async-задачи (`calculateTotalAmountAsync`).
        // Ждать нужно ОБА условия — иначе на медленном раннере тест мог поймать промежуточное
        // состояние (словарь уже полон, totalAmount ещё 0.0 по умолчанию) и false-negative упасть
        // на последней проверке инварианта ниже (flake, найден фикс-раундом верификатора).
        let propagated = await waitForAsyncStatePropagation {
            viewModel.state.groupTotalsPrimaryCurrency[coreGroupA.groupUniqueID] != nil
                && viewModel.state.groupTotalsPrimaryCurrency[coreGroupB.groupUniqueID] != nil
                && viewModel.state.totalAmount != 0
        }
        #expect(propagated, "groupTotalsPrimaryCurrency И totalAmount должны заполниться после loadGroups/loadAccounts")

        let totalA = try #require(viewModel.state.groupTotalsPrimaryCurrency[coreGroupA.groupUniqueID])
        let totalB = try #require(viewModel.state.groupTotalsPrimaryCurrency[coreGroupB.groupUniqueID])
        #expect(abs(totalA - 500_000) < 0.01, "Группа с наличными — чистый актив")
        #expect(totalB < 0, "Группа с кредитом — чистое обязательство (знак применяется движком баланса)")

        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: [coreGroupA.groupUniqueID, coreGroupB.groupUniqueID],
            totalsInPrimaryCurrency: viewModel.state.groupTotalsPrimaryCurrency,
            ungroupedTotal: viewModel.state.ungroupedTotal
        )

        #expect(split.assets.groupIDs.contains(coreGroupA.groupUniqueID))
        #expect(split.liabilities.groupIDs.contains(coreGroupB.groupUniqueID))
        #expect(split.ungroupedInAssets == true, "Ungrouped с наличными 150 000 — актив")

        let sectionsSum = split.assets.subtotal + split.liabilities.subtotal
        #expect(
            abs(sectionsSum - viewModel.state.totalAmount) < 0.01,
            "Сумма подытогов секций обязана совпадать с тоталом шапки (single source of truth)"
        )
    }

    /// [Документированный AC-gap, НЕ баг — инвариант 9 §2.1 плана 5c.7] На честном mixed-store (core-
    /// группа с одноимённой непроконвертированной легаси-`FinanceGroup`) подытоги секций и тотал шапки
    /// РАСХОДЯТСЯ by construction: `calculateGroupTotal`/`groupTotalsPrimaryCurrency` матчит легаси-
    /// хвост по имени и складывает его в подытог (тот же путь, что уже красит бейдж строки группы —
    /// поведение сознательно НЕ меняем), а `state.totalAmount` (шапка «Счетов») — single-world
    /// core-only агрегат (6b Фаза 2, `calculateTotalsSnapshot`), легаси-хвост туда не входит. Это
    /// переходный эффект до ручной конвертации/очистки легаси-пары владельцем, не регресс Гейта
    /// 5c.7.6.2 — тест фиксирует ТЕКУЩЕЕ поведение (characterization), чтобы будущий рефакторинг не
    /// "исправил" его молча в любую сторону без осознанного решения.
    @Test("[Характеризация] Mixed-store: подытог группы включает легаси-хвост, тотал шапки — нет; расхождение == сумме хвоста")
    func mixedStoreSubtotalIncludesLegacyTailButHeaderDoesNot() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-30 * 86_400)

        // Core-группа + ОДНОИМЁННАЯ легаси-FinanceGroup (непроконвертированный хвост, invariant 9 §2.1,
        // мост по имени — `FinanceViewModel.fetchLegacyGroup(named:)`).
        let coreGroup = AccountGroup(name: "Смешанная группа")
        ctx.insert(coreGroup)
        let legacyGroup = FinanceGroup(name: "Смешанная группа", colorHex: "#111111")
        ctx.insert(legacyGroup)

        let accountsService = AccountsCoreService(modelContext: ctx)
        _ = try accountsService.createAccount(
            name: "Core-наличные", kind: .cash, currency: "RUB", openingBalance: 500_000,
            group: coreGroup, date: createdAt
        )

        let card = Card(name: "Легаси карта", cardNumber: "1111", cardType: .debit, currency: "RUB", balance: 200_000)
        card.createdAt = createdAt
        card.initialBalance = 200_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = legacyGroup
        legacyGroup.accounts = [legacyAccount]
        ctx.insert(legacyAccount)
        try ctx.save()

        let viewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        viewModel.handle(.loadGroups)
        viewModel.handle(.loadAccounts)

        let propagated = await waitForAsyncStatePropagation {
            viewModel.state.groupTotalsPrimaryCurrency[coreGroup.groupUniqueID] != nil
                && viewModel.state.totalAmount != 0
        }
        #expect(propagated)

        let groupTotal = try #require(viewModel.state.groupTotalsPrimaryCurrency[coreGroup.groupUniqueID])
        #expect(abs(groupTotal - 700_000) < 0.01, "Подытог группы = core (500 000) + легаси-хвост (200 000)")
        #expect(abs(viewModel.state.totalAmount - 500_000) < 0.01, "Тотал шапки — только core (500 000), легаси-хвост не учтён")

        let split = FinanceAccountsSectionSplitter.split(
            orderedGroupIDs: [coreGroup.groupUniqueID],
            totalsInPrimaryCurrency: viewModel.state.groupTotalsPrimaryCurrency,
            ungroupedTotal: nil
        )
        let sectionsSum = split.assets.subtotal + split.liabilities.subtotal
        let gap = sectionsSum - viewModel.state.totalAmount
        #expect(abs(gap - 200_000) < 0.01, "Расхождение подытогов и шапки равно ровно легаси-хвосту — документированный эффект, не регресс")
    }
}
