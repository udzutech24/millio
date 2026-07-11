import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.3 → [Ф5c.7 contract, портировано] CHARACTERIZATION-тесты `FinanceViewModel` — числа
/// СОХРАНЕНЫ после атомарного флипа (`state.groups`→`[AccountGroup]`, `orderedAccounts`→core-primary,
/// `calculateGroupTotal`→core-primary+legacy-fallback-по-имени). Где сигнатура метода сменила
/// первичный тип (`orderedAccounts`/`visibleGroupsForList` теперь принимают/возвращают `AccountGroup`,
/// не `FinanceGroup`) — фикстуры адаптированы на core, при сохранении АССЕРТИРУЕМОГО контракта
/// (сумма/сортировка/фильтр), не только счётчика прохождения.
@Suite(.serialized)
@MainActor
struct FinanceViewModelCharacterizationTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")

        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        let vm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(vm)
        return vm
    }

    // MARK: - Totals

    /// Легаси-группа только из легаси-счетов, все в RUB, БЕЗ одноимённой core-группы: тотал = легаси
    /// fallback-сумма без конвертации (core-терм = 0, т.к. `fetchLegacyGroup` находит "Осн").
    @Test("characterization: тотал легаси-группы (RUB) = 12000 + 8000 = 20000")
    func legacyOnlyGroupTotal() async throws {
        let ctx = try makeContext()
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF", order: 0)
        group.displayCurrency = "RUB"
        ctx.insert(group)
        // Одноимённая core-группа — ПУСТАЯ (coreTotal=0), нужна как primary-точка входа в
        // `calculateGroupTotal(group: AccountGroup, ...)` после флипа.
        let coreGroup = AccountGroup(name: "Осн")
        ctx.insert(coreGroup)

        let c1 = Card(name: "A", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 12_000)
        let c2 = Card(name: "B", cardNumber: "2222", bank: .other, cardType: .debit, currency: "RUB", balance: 8_000)
        c1.includeInTotal = true
        c2.includeInTotal = true
        ctx.insert(c1); ctx.insert(c2)
        for card in [c1, c2] {
            let j = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
            j.group = group
            ctx.insert(j)
        }
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)

        let total = await vm.calculateGroupTotal(group: coreGroup, in: "RUB")
        #expect(abs(total - 20_000) < 0.01)
    }

    /// СМЕШАННЫЙ стор (инвариант 9 §2.1): легаси-счёт + core-счёт под одноимённой группой одновременно.
    /// `calculateGroupTotal` = coreTotal(7000) + legacyTotal-fallback(10000) = 17000; легаси-хвост НЕ теряется.
    @Test("characterization mixed-store: тотал = легаси 10000 + core 7000 = 17000, легаси-хвост виден")
    func mixedStoreGroupTotal() async throws {
        let ctx = try makeContext()

        let legacyGroup = FinanceGroup(name: "Микс", colorHex: "#123456", order: 0)
        legacyGroup.displayCurrency = "RUB"
        ctx.insert(legacyGroup)
        let legacyCard = Card(name: "Легаси", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        legacyCard.includeInTotal = true
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = legacyGroup
        ctx.insert(junction)

        let coreGroup = AccountGroup(name: "Микс")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(
            name: "Core", kind: .debitCard, currency: "RUB", openingBalance: 7_000, group: coreGroup
        )
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)

        // Инвариант 9: легаси-хвост найден под core-группой по имени (name-мост).
        #expect(vm.newCoreAccounts(matchingName: legacyGroup.name).count == 1)

        let total = await vm.calculateGroupTotal(group: coreGroup, in: "RUB")
        #expect(abs(total - 17_000) < 0.01)
    }

    // MARK: - Ordering

    /// [Ф5c.7 contract] `orderedAccounts(for:)` теперь core-primary — фикстура портирована на core-счета
    /// (было: легаси `FinanceAccount`). Контракт сохранён: сортировка по сумме убыв. =
    /// [large(300), medium(200), small(100)].
    @Test("characterization: orderedAccounts по сумме убыв. = [large, medium, small]")
    func orderedAccountsByAmountDescending() throws {
        let ctx = try makeContext()
        let group = AccountGroup(name: "Осн")
        ctx.insert(group)

        let coreService = AccountsCoreService(modelContext: ctx)
        let small = try coreService.createAccount(name: "Small", kind: .debitCard, currency: "RUB", openingBalance: 100, group: group)
        let large = try coreService.createAccount(name: "Large", kind: .debitCard, currency: "RUB", openingBalance: 300, group: group)
        let medium = try coreService.createAccount(name: "Medium", kind: .debitCard, currency: "RUB", openingBalance: 200, group: group)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        let loaded = try #require(vm.state.groups.first)
        #expect(vm.orderedAccounts(for: loaded).map(\.id) == [large.id, medium.id, small.id])
    }

    // MARK: - Filters

    /// [Ф5c.7 contract] Ungrouped структурно НЕ входит в `[AccountGroup]` (канон `group == nil`,
    /// гард в `loadCoreEntities`) — сильнее старого поведения «скрыт, если пуст»: теперь физически
    /// невозможен как элемент `visibleGroupsForList()`, не просто отфильтрован.
    @Test("characterization: visibleGroupsForList не содержит Ungrouped, показывает непустую группу")
    func visibleGroupsHidesEmptyUngrouped() throws {
        let ctx = try makeContext()
        let visible = AccountGroup(name: "Видимая", order: 1)
        ctx.insert(visible)
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "C", kind: .debitCard, currency: "RUB", openingBalance: 500, group: visible)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        let names = vm.visibleGroupsForList().map(\.name)
        #expect(names.contains("Видимая"))
        #expect(!names.contains(FinanceSystemGroups.ungroupedName))
    }

    /// `newCoreAccounts(matchingName:)` отдаёт только участвующие сегодня (архивные core-счета скрыты).
    @Test("characterization: newCoreAccounts исключает архивный core-счёт (participates)")
    func newCoreAccountsExcludesArchived() throws {
        let ctx = try makeContext()
        let legacyGroup = FinanceGroup(name: "Жизнь", colorHex: "#222222", order: 0)
        ctx.insert(legacyGroup)
        let coreGroup = AccountGroup(name: "Жизнь")
        ctx.insert(coreGroup)

        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Актив", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: coreGroup)
        let archived = try coreService.createAccount(name: "Архив", kind: .debitCard, currency: "RUB", openingBalance: 2_000, group: coreGroup)
        archived.archivedAt = Date().addingTimeInterval(-86_400) // архивирован вчера → не participates сегодня
        try ctx.save()

        let vm = makeViewModel(ctx)
        let core = vm.newCoreAccounts(matchingName: legacyGroup.name)
        #expect(core.count == 1)
        #expect(core.first?.name == "Актив")
    }
}
