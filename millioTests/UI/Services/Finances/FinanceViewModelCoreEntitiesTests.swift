import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.4 expand-шаг №1 — populate `state.coreGroups`/`state.coreAccounts` РЯДОМ с легаси-полями.
///
/// Назначение: зафиксировать, что новые core-поля наполняются в том же lifecycle, что `state.groups`,
/// БЕЗ смены легаси-поведения (потребителей ещё нет — dead-read до пофайловой миграции). Инвариант 9
/// §2.1: fixture держит core-счета и непроконвертированный легаси-счёт ОДНОВРЕМЕННО.
///
/// Контейнер — полный миграционный (как в `FinanceViewModelCharacterizationTests`): базовый
/// `FinanceViewModelTests.schema` не содержит `Account`/`AccountGroup`.
@Suite(.serialized)
@MainActor
struct FinanceViewModelCoreEntitiesTests {

    // Держим контейнеры/VM живыми: `loadAccounts` планирует fire-and-forget Task, трогающий store
    // после возврата из теста (тот же приём, что в characterization-сьюте).
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

    /// MIXED-STORE (инвариант 9 §2.1): core-счёт в группе + core-счёт БЕЗ группы + непроконвертированный
    /// легаси-счёт одновременно. После loadGroups: coreAccounts содержит оба core-счёта, coreGroups без
    /// Ungrouped, легаси-путь (`state.groups`/`calculateGroupTotal`) не изменился.
    @Test("expand#1 mixed-store: coreAccounts содержит core-счета, coreGroups без Ungrouped, легаси не тронуто")
    func mixedStorePopulatesCoreEntitiesBesideLegacy() async throws {
        let ctx = try makeContext()

        // Core-часть: группа "Инвест" + core-счёт в ней + core-счёт БЕЗ группы (Ungrouped-канон).
        let coreGroup = AccountGroup(name: "Инвест")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        let grouped = try coreService.createAccount(
            name: "CoreГруппа", kind: .debitCard, currency: "RUB", openingBalance: 5_000, group: coreGroup
        )
        let ungrouped = try coreService.createAccount(
            name: "CoreБезГруппы", kind: .debitCard, currency: "RUB", openingBalance: 3_000, group: nil
        )

        // Легаси-часть: непроконвертированный легаси-счёт + FinanceGroup + junction.
        let legacyGroup = FinanceGroup(name: "Легаси", colorHex: "#123456", order: 0)
        legacyGroup.displayCurrency = "RUB"
        ctx.insert(legacyGroup)
        let legacyCard = Card(name: "ЛегасиКарта", cardNumber: "9999", bank: .other, cardType: .debit, currency: "RUB", balance: 10_000)
        legacyCard.includeInTotal = true
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = legacyGroup
        ctx.insert(junction)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        vm.handle(.loadAccounts)

        // (1) coreAccounts содержит оба core-счёта.
        let coreIDs = Set(vm.state.coreAccounts.map(\.id))
        #expect(coreIDs.contains(grouped.id))
        #expect(coreIDs.contains(ungrouped.id))

        // (2) coreGroups содержит реальную группу и НЕ содержит Ungrouped-сущности.
        #expect(vm.state.coreGroups.map(\.name).contains("Инвест"))
        #expect(!vm.state.coreGroups.map(\.name).contains(FinanceSystemGroups.ungroupedName))

        // (3) Счёт без группы виден через канон `group == nil`.
        let ungroupedCore = vm.state.coreAccounts.filter { $0.group == nil }
        #expect(ungroupedCore.map(\.id) == [ungrouped.id])

        // (4) Легаси-поля не изменились относительно characterization-ожиданий: группа видна,
        //     тотал по легаси-группе = 10000 (легаси-карта; core-счёта с именем "Легаси" нет).
        #expect(vm.state.groups.map(\.name).contains("Легаси"))
        let legacyTotal = await vm.calculateGroupTotal(group: legacyGroup, in: "RUB")
        #expect(abs(legacyTotal - 10_000) < 0.01)
    }

    /// Пустой core-стор: поля инициализированы пустыми массивами, легаси-populate не падает.
    @Test("expand#1: пустой core-стор → coreAccounts/coreGroups пусты, без краша")
    func emptyCoreStoreYieldsEmptyArrays() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.coreAccounts.isEmpty)
        #expect(vm.state.coreGroups.isEmpty)
    }

    /// Архивный core-счёт не попадает в coreAccounts (participates-семантика, как у `newCoreAccounts`).
    @Test("expand#1: архивный core-счёт исключён из coreAccounts")
    func archivedCoreAccountExcluded() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let active = try coreService.createAccount(name: "Актив", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)
        let archived = try coreService.createAccount(name: "Архив", kind: .debitCard, currency: "RUB", openingBalance: 2_000, group: nil)
        archived.archivedAt = Date().addingTimeInterval(-86_400) // архивирован вчера → не participates
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        let ids = Set(vm.state.coreAccounts.map(\.id))
        #expect(ids.contains(active.id))
        #expect(!ids.contains(archived.id))
    }

    // MARK: - Миграция потребителя `FinanceRows` (Ф5c.7.4, файл №1)

    /// Паритет: новый локальный фильтр `FinanceRows.newCoreAccounts` (реплицирован здесь, т.к. View
    /// напрямую не юнит-тестируется) обязан отдавать ТЕ ЖЕ ID, что старый живой
    /// `vm.newCoreAccounts(matching:)`, на фикстуре с ДВУМЯ именованными группами + Ungrouped-канон —
    /// доказывает, что смена источника данных (state.coreAccounts вместо fetch) поведенчески нейтральна.
    @Test("expand#1 FinanceRows-паритет: filter(state.coreAccounts) == newCoreAccounts(matching:) для 2 групп + Ungrouped")
    func financeRowsFilterParityWithLiveFetch() throws {
        let ctx = try makeContext()
        let groupA = FinanceGroup(name: "Группа А", colorHex: "#111111", order: 0)
        let groupB = FinanceGroup(name: "Группа Б", colorHex: "#222222", order: 1)
        ctx.insert(groupA); ctx.insert(groupB)
        let coreGroupA = AccountGroup(name: "Группа А")
        ctx.insert(coreGroupA)

        let coreService = AccountsCoreService(modelContext: ctx)
        let inA = try coreService.createAccount(name: "A1", kind: .debitCard, currency: "RUB", openingBalance: 100, group: coreGroupA)
        let ungrouped = try coreService.createAccount(name: "U1", kind: .debitCard, currency: "RUB", openingBalance: 200, group: nil)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        // Реплика фильтра FinanceRows.newCoreAccounts (см. FinanceRows.swift) — сверяем с живым методом.
        func rowsFilter(for group: FinanceGroup) -> [Account] {
            if group.name == FinanceSystemGroups.ungroupedName {
                return vm.state.coreAccounts.filter { $0.group == nil }
            }
            let targetName = group.name
            return vm.state.coreAccounts.filter { $0.group?.name == targetName }
        }

        #expect(Set(rowsFilter(for: groupA).map(\.id)) == Set(vm.newCoreAccounts(matching: groupA).map(\.id)))
        #expect(rowsFilter(for: groupA).map(\.id) == [inA.id])
        #expect(Set(rowsFilter(for: groupB).map(\.id)) == Set(vm.newCoreAccounts(matching: groupB).map(\.id)))
        #expect(rowsFilter(for: groupB).isEmpty)

        let ungroupedLegacy = FinanceGroup(name: FinanceSystemGroups.ungroupedName, colorHex: "#333333", order: 2)
        #expect(rowsFilter(for: ungroupedLegacy).map(\.id) == [ungrouped.id])
        #expect(Set(rowsFilter(for: ungroupedLegacy).map(\.id)) == Set(vm.newCoreAccounts(matching: ungroupedLegacy).map(\.id)))
    }

    /// Компаньон-фикс: `.hideAddAccountSheet` обязан освежать `state.coreAccounts`, иначе core-счёт,
    /// созданный в открытом sheet'е (EventBus/`loadGroups` там не вызывается), не появится в
    /// `FinanceRows` после перевода на `state.coreAccounts` (регресс, которого не было при живом fetch).
    @Test("expand#1: .hideAddAccountSheet освежает state.coreAccounts (регресс-guard компаньон-фикса)")
    func hideAddAccountSheetRefreshesCoreAccounts() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.coreAccounts.isEmpty)

        // Симулируем создание core-счёта, пока sheet был открыт (тем же путём, что
        // `FinanceAddAccountView.createMoneyAccountOnNewCore` — минуя EventBus/loadGroups).
        let coreService = AccountsCoreService(modelContext: ctx)
        let created = try coreService.createAccount(name: "Новый", kind: .debitCard, currency: "RUB", openingBalance: 500, group: nil)

        // Без reload — состояние ещё не видит новый счёт (доказывает, что регресс был бы реальным).
        #expect(!vm.state.coreAccounts.map(\.id).contains(created.id))

        vm.handle(.hideAddAccountSheet)
        #expect(vm.state.coreAccounts.map(\.id).contains(created.id))
    }

    // MARK: - Root-фикс (Fable-находка): общий EventBus-рефреш для archive/restore/delete/update/QuickSetup

    /// archiveAccount публикует `investmentsUpdated` (см. `AccountDetailView.archiveAccount()`) —
    /// `subscribeToFinanceEvents` обязан освежить `state.coreAccounts`, иначе архивный счёт остаётся
    /// ghost-строкой в `FinanceRows` (Fable-находка №2).
    @Test("root-фикс: archive исключает счёт из state.coreAccounts после investmentsUpdated")
    func archiveViaEventPublishExcludesAccountFromCoreAccounts() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "К архиву", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.coreAccounts.map(\.id).contains(account.id))

        try coreService.archiveAccount(account) // как AccountDetailView.archiveAccount()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)

        #expect(!vm.state.coreAccounts.map(\.id).contains(account.id))
    }

    /// restoreAccount (ArchivedAccountsView) теперь публикует то же событие — счёт обязан вернуться
    /// в снапшот (Fable-находка №3, было: "НЕ публикуют событий вообще, только refreshToken").
    @Test("root-фикс: restore возвращает счёт в state.coreAccounts после investmentsUpdated")
    func restoreViaEventPublishReappearsInCoreAccounts() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Архивный", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)
        try coreService.archiveAccount(account)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(!vm.state.coreAccounts.map(\.id).contains(account.id))

        try coreService.restoreAccount(account)
        EventBus.shared.publish(FinanceEvent.investmentsUpdated) // как ArchivedAccountsView.restore()

        #expect(vm.state.coreAccounts.map(\.id).contains(account.id))
    }

    /// physicallyDelete теперь публикует событие — счёт обязан пропасть из снапшота БЕЗ висячей
    /// ссылки на удалённый @Model (Fable-находка №3: риск краша NavigationLink в FinanceRows).
    @Test("root-фикс: physicallyDelete убирает счёт из state.coreAccounts, висячей ссылки нет")
    func physicallyDeleteViaEventPublishLeavesNoDanglingReference() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "На удаление", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)
        try coreService.archiveAccount(account) // physicallyDelete доступен только для архивных (UI-гейт)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        try coreService.physicallyDelete(account)
        EventBus.shared.publish(FinanceEvent.investmentsUpdated) // как ArchivedAccountsView.confirmPhysicalDeletion()

        #expect(vm.state.coreAccounts.first(where: { $0.id == account.id }) == nil)
    }

    /// updateAccount со сменой группы (performEdit) обязан переносить счёт в новый бакет
    /// FinanceRows-фильтра (Fable-находка №4), не оставлять в старом.
    @Test("root-фикс: updateAccount(группа) переносит счёт в новый бакет FinanceRows-фильтра")
    func updateAccountGroupChangeMovesToNewBucket() throws {
        let ctx = try makeContext()
        let groupA = AccountGroup(name: "А")
        let groupB = AccountGroup(name: "Б")
        ctx.insert(groupA); ctx.insert(groupB)
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Мигрант", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: groupA)

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        func bucket(_ name: String) -> [Account] {
            vm.state.coreAccounts.filter { $0.group?.name == name }
        }
        #expect(bucket("А").map(\.id) == [account.id])
        #expect(bucket("Б").isEmpty)

        _ = try coreService.updateAccount(account, name: account.name, group: groupB) // как performEdit()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)

        #expect(bucket("А").isEmpty)
        #expect(bucket("Б").map(\.id) == [account.id])
    }

    /// adjustBalance (perform(), без публикации событий) — баланс в строке обязан обновляться БЕЗ
    /// рефреша снапшота: `state.coreAccounts` хранит ту же @Model-ссылку, что и `modelContext`
    /// (единый контекст), поэтому `newCoreBalanceToday` пересчитывает по актуальным `.events`
    /// даже без `loadCoreEntities()`. Доказывает Fable-предположение №6 тестом, не пересказом.
    @Test("root-фикс: adjustBalance обновляет баланс в снапшоте без явного рефреша (живая @Model-ссылка)")
    func adjustBalanceReflectsLiveWithoutSnapshotRefresh() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Живой баланс", kind: .debitCard, currency: "RUB", openingBalance: 1_000)

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        let accountInSnapshot = try #require(vm.state.coreAccounts.first)
        #expect(vm.newCoreBalanceToday(accountInSnapshot) == 1_000)

        // Мутируем ТУ ЖЕ @Model-ссылку через сервис на том же modelContext — намеренно НЕ вызываем
        // loadGroups/loadCoreEntities/EventBus.publish здесь: проверяем именно "без рефреша".
        _ = try coreService.adjustBalance(account: accountInSnapshot, to: 1_500)

        #expect(vm.newCoreBalanceToday(accountInSnapshot) == 1_500)
    }
}
