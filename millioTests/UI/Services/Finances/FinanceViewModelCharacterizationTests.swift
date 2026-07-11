import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.3 — CHARACTERIZATION-тесты `FinanceViewModel` (снимок ТЕКУЩЕГО легаси-поведения ДО порта).
///
/// Назначение (Fable-риск №5, план §5c.7.3): зафиксировать totals/ordering/фильтры с КОНКРЕТНЫМИ
/// числами на легаси-коде, чтобы будущий атомарный тип-флип (`state.groups`→`[AccountGroup]`,
/// `availableCards`→`[Account]`) нельзя было «подтвердить» переписанным вместе с ним тестом. Эти
/// ожидаемые числа — контракт: после порта они обязаны совпасть (лишь сигнатуры вызовов адаптируются).
///
/// Почему отдельный файл со своим контейнером: базовый `FinanceViewModelTests.schema` (строки 194-203)
/// НЕ содержит core-моделей (`Account`/`AccountEvent`/`AccountGroup`) — а characterization mixed-store
/// (инвариант 9 §2.1) обязан держать core и легаси ОДНОВРЕМЕННО. Берём полный контейнер миграции.
@Suite(.serialized)
@MainActor
struct FinanceViewModelCharacterizationTests {

    // Удерживаем контейнеры и VM живыми на время сьюта: `loadAccounts` планирует fire-and-forget
    // background Task (`calculateTotalAmount`→`calculateTotalsSnapshot`), который трогает store уже
    // после возврата из теста. Если контейнер/VM успеют деаллоцироваться — задача падает на store и
    // роняет тест-хост (relaunch между кейсами). Тот же приём, что `FinanceViewModelTests.retainedContainers`.
    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        // RUB как основная — чтобы RUB-суммы не конвертировались (детерминизм без зависимости от курсов).
        let defaults = UserDefaults.standard
        defaults.set("RUB", forKey: "primaryCurrencyCode")
        defaults.set(false, forKey: "finance_savings_goal_enabled")
        defaults.set(0, forKey: "finance_savings_goal_amount")

        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        // Мок курсов: from==to → 1.0, поэтому RUB→RUB не искажается; сеть не дёргается.
        let vm = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        Self.retained.append(vm)
        return vm
    }

    // MARK: - Totals

    /// Легаси-группа только из легаси-счетов, все в RUB: тотал == сумме балансов без конвертации.
    @Test("characterization: тотал легаси-группы (RUB) = 12000 + 8000 = 20000")
    func legacyOnlyGroupTotal() async throws {
        let ctx = try makeContext()
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF", order: 0)
        group.displayCurrency = "RUB"
        ctx.insert(group)

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

        let total = await vm.calculateGroupTotal(group: group, in: "RUB")
        #expect(abs(total - 20_000) < 0.01)
    }

    /// СМЕШАННЫЙ стор (инвариант 9 §2.1): легаси-счёт + core-счёт под одноимённой группой одновременно.
    /// `calculateGroupTotal` = legacyTotal(10000) + coreTotal(7000) = 17000; core-хвост НЕ теряется.
    @Test("characterization mixed-store: тотал = легаси 10000 + core 7000 = 17000, core-хвост виден")
    func mixedStoreGroupTotal() async throws {
        let ctx = try makeContext()

        // Легаси-часть: FinanceGroup "Микс" + легаси-карта 10000 через junction.
        let legacyGroup = FinanceGroup(name: "Микс", colorHex: "#123456", order: 0)
        legacyGroup.displayCurrency = "RUB"
        ctx.insert(legacyGroup)
        let legacyCard = Card(name: "Легаси", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        legacyCard.includeInTotal = true
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = legacyGroup
        ctx.insert(junction)

        // Core-часть: AccountGroup с ТЕМ ЖЕ именем (мост по имени) + core-счёт 7000.
        let coreGroup = AccountGroup(name: "Микс")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(
            name: "Core", kind: .debitCard, currency: "RUB", openingBalance: 7_000, group: coreGroup
        )
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadAccounts)

        // Инвариант 9: core-хвост найден под легаси-группой по имени.
        #expect(vm.newCoreAccounts(matching: legacyGroup).count == 1)

        let total = await vm.calculateGroupTotal(group: legacyGroup, in: "RUB")
        #expect(abs(total - 17_000) < 0.01)
    }

    // MARK: - Ordering

    /// Сортировка по сумме (по убыванию) — дефолтный режим. Ожидаемый порядок ID: large(300) → medium(200) → small(100).
    @Test("characterization: orderedAccounts по сумме убыв. = [large, medium, small]")
    func orderedAccountsByAmountDescending() throws {
        let ctx = try makeContext()
        let group = FinanceGroup(name: "Осн", colorHex: "#FFFFFF", order: 0)
        ctx.insert(group)

        let small = Card(name: "Small", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 100)
        let large = Card(name: "Large", cardNumber: "2222", bank: .other, cardType: .debit, currency: "RUB", balance: 300)
        let medium = Credit(
            name: "Medium", amount: 1_000, interestRate: 10, monthlyPayment: 100,
            startDate: Date(), termMonths: 12, currency: "RUB", bank: .other, creditType: .consumer
        )
        medium.remainingAmount = 200
        ctx.insert(small); ctx.insert(large); ctx.insert(medium)
        for (acc, id) in [(FinanceAccountType.card, small.cardUniqueID), (.card, large.cardUniqueID), (.credit, medium.creditUniqueID)] {
            let j = FinanceAccount(accountType: acc, accountID: id)
            j.group = group
            ctx.insert(j)
        }
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        vm.handle(.loadAccounts)

        let loaded = try #require(vm.state.groups.first)
        #expect(vm.orderedAccounts(for: loaded).map(\.accountID) == [
            large.cardUniqueID, medium.creditUniqueID, small.cardUniqueID,
        ])
    }

    // MARK: - Filters

    /// Пустая системная «Без группы» скрыта из списка, обычная группа с легаси-счётом — видна.
    @Test("characterization: visibleGroupsForList скрывает пустой Ungrouped, показывает непустую группу")
    func visibleGroupsHidesEmptyUngrouped() throws {
        let ctx = try makeContext()
        let ungrouped = FinanceGroup(name: FinanceSystemGroups.ungroupedName, colorHex: FinanceSystemGroups.ungroupedColorHex, order: 0)
        ctx.insert(ungrouped)
        let visible = FinanceGroup(name: "Видимая", colorHex: "#111111", order: 1)
        ctx.insert(visible)
        let card = Card(name: "C", cardNumber: "1111", bank: .other, cardType: .debit, currency: "RUB", balance: 500)
        ctx.insert(card)
        let j = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        j.group = visible
        ctx.insert(j)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        vm.handle(.loadAccounts)

        let names = vm.visibleGroupsForList().map(\.name)
        #expect(names.contains("Видимая"))
        #expect(!names.contains(FinanceSystemGroups.ungroupedName))
    }

    /// `newCoreAccounts(matching:)` отдаёт только участвующие сегодня (архивные core-счета скрыты).
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
        let core = vm.newCoreAccounts(matching: legacyGroup)
        #expect(core.count == 1)
        #expect(core.first?.name == "Актив")
    }
}
