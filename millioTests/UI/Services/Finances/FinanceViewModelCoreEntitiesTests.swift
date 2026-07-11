import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.4 expand-шаг №1 — populate `state.groups`/`state.accounts` РЯДОМ с легаси-полями.
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
        // Пустая одноимённая core-группа — точка входа для `calculateGroupTotal(group: AccountGroup,...)`
        // (легаси-хвост считается fallback'ом по имени, coreTotal здесь 0).
        let legacyGroupCoreEntry = AccountGroup(name: "Легаси")
        ctx.insert(legacyGroupCoreEntry)
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
        let coreIDs = Set(vm.state.accounts.map(\.id))
        #expect(coreIDs.contains(grouped.id))
        #expect(coreIDs.contains(ungrouped.id))

        // (2) coreGroups содержит реальную группу и НЕ содержит Ungrouped-сущности.
        #expect(vm.state.groups.map(\.name).contains("Инвест"))
        #expect(!vm.state.groups.map(\.name).contains(FinanceSystemGroups.ungroupedName))

        // (3) Счёт без группы виден через канон `group == nil`.
        let ungroupedCore = vm.state.accounts.filter { $0.group == nil }
        #expect(ungroupedCore.map(\.id) == [ungrouped.id])

        // (4) Легаси-поля не изменились относительно characterization-ожиданий: группа видна,
        //     тотал по легаси-группе = 10000 (легаси-карта; core-счёта с именем "Легаси" нет).
        #expect(vm.state.groups.map(\.name).contains("Легаси"))
        let legacyTotal = await vm.calculateGroupTotal(group: legacyGroupCoreEntry, in: "RUB")
        #expect(abs(legacyTotal - 10_000) < 0.01)
    }

    /// Пустой core-стор: поля инициализированы пустыми массивами, легаси-populate не падает.
    @Test("expand#1: пустой core-стор → coreAccounts/coreGroups пусты, без краша")
    func emptyCoreStoreYieldsEmptyArrays() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.accounts.isEmpty)
        #expect(vm.state.groups.isEmpty)
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

        let ids = Set(vm.state.accounts.map(\.id))
        #expect(ids.contains(active.id))
        #expect(!ids.contains(archived.id))
    }

    // MARK: - Миграция потребителя `FinanceRows` (Ф5c.7.4, файл №1)

    /// Паритет: новый локальный фильтр `FinanceRows.newCoreAccounts` (реплицирован здесь, т.к. View
    /// напрямую не юнит-тестируется) обязан отдавать ТЕ ЖЕ ID, что старый живой
    /// `vm.newCoreAccounts(matching:)`, на фикстуре с ДВУМЯ именованными группами + Ungrouped-канон —
    /// доказывает, что смена источника данных (state.accounts вместо fetch) поведенчески нейтральна.
    @Test("expand#1 FinanceRows-паритет: filter(state.accounts) == newCoreAccounts(matching:) для 2 групп + Ungrouped")
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
                return vm.state.accounts.filter { $0.group == nil }
            }
            let targetName = group.name
            return vm.state.accounts.filter { $0.group?.name == targetName }
        }

        #expect(Set(rowsFilter(for: groupA).map(\.id)) == Set(vm.newCoreAccounts(matchingName: groupA.name).map(\.id)))
        #expect(rowsFilter(for: groupA).map(\.id) == [inA.id])
        #expect(Set(rowsFilter(for: groupB).map(\.id)) == Set(vm.newCoreAccounts(matchingName: groupB.name).map(\.id)))
        #expect(rowsFilter(for: groupB).isEmpty)

        let ungroupedLegacy = FinanceGroup(name: FinanceSystemGroups.ungroupedName, colorHex: "#333333", order: 2)
        #expect(rowsFilter(for: ungroupedLegacy).map(\.id) == [ungrouped.id])
        #expect(Set(rowsFilter(for: ungroupedLegacy).map(\.id)) == Set(vm.newCoreAccounts(matchingName: ungroupedLegacy.name).map(\.id)))
    }

    /// Компаньон-фикс: `.hideAddAccountSheet` обязан освежать `state.accounts`, иначе core-счёт,
    /// созданный в открытом sheet'е (EventBus/`loadGroups` там не вызывается), не появится в
    /// `FinanceRows` после перевода на `state.accounts` (регресс, которого не было при живом fetch).
    @Test("expand#1: .hideAddAccountSheet освежает state.accounts (регресс-guard компаньон-фикса)")
    func hideAddAccountSheetRefreshesCoreAccounts() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.accounts.isEmpty)

        // Симулируем создание core-счёта, пока sheet был открыт (тем же путём, что
        // `FinanceAddAccountView.createMoneyAccountOnNewCore` — минуя EventBus/loadGroups).
        let coreService = AccountsCoreService(modelContext: ctx)
        let created = try coreService.createAccount(name: "Новый", kind: .debitCard, currency: "RUB", openingBalance: 500, group: nil)

        // Без reload — состояние ещё не видит новый счёт (доказывает, что регресс был бы реальным).
        #expect(!vm.state.accounts.map(\.id).contains(created.id))

        vm.handle(.hideAddAccountSheet)
        #expect(vm.state.accounts.map(\.id).contains(created.id))
    }

    // MARK: - Root-фикс (Fable-находка): общий EventBus-рефреш для archive/restore/delete/update/QuickSetup

    /// archiveAccount публикует `investmentsUpdated` (см. `AccountDetailView.archiveAccount()`) —
    /// `subscribeToFinanceEvents` обязан освежить `state.accounts`, иначе архивный счёт остаётся
    /// ghost-строкой в `FinanceRows` (Fable-находка №2).
    @Test("root-фикс: archive исключает счёт из state.accounts после investmentsUpdated")
    func archiveViaEventPublishExcludesAccountFromCoreAccounts() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "К архиву", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.state.accounts.map(\.id).contains(account.id))

        try coreService.archiveAccount(account) // как AccountDetailView.archiveAccount()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)

        #expect(!vm.state.accounts.map(\.id).contains(account.id))
    }

    /// restoreAccount (ArchivedAccountsView) теперь публикует то же событие — счёт обязан вернуться
    /// в снапшот (Fable-находка №3, было: "НЕ публикуют событий вообще, только refreshToken").
    @Test("root-фикс: restore возвращает счёт в state.accounts после investmentsUpdated")
    func restoreViaEventPublishReappearsInCoreAccounts() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Архивный", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: nil)
        try coreService.archiveAccount(account)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(!vm.state.accounts.map(\.id).contains(account.id))

        try coreService.restoreAccount(account)
        EventBus.shared.publish(FinanceEvent.investmentsUpdated) // как ArchivedAccountsView.restore()

        #expect(vm.state.accounts.map(\.id).contains(account.id))
    }

    /// physicallyDelete теперь публикует событие — счёт обязан пропасть из снапшота БЕЗ висячей
    /// ссылки на удалённый @Model (Fable-находка №3: риск краша NavigationLink в FinanceRows).
    @Test("root-фикс: physicallyDelete убирает счёт из state.accounts, висячей ссылки нет")
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

        #expect(vm.state.accounts.first(where: { $0.id == account.id }) == nil)
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
            vm.state.accounts.filter { $0.group?.name == name }
        }
        #expect(bucket("А").map(\.id) == [account.id])
        #expect(bucket("Б").isEmpty)

        _ = try coreService.updateAccount(account, name: account.name, group: groupB) // как performEdit()
        EventBus.shared.publish(FinanceEvent.investmentsUpdated)

        #expect(bucket("А").isEmpty)
        #expect(bucket("Б").map(\.id) == [account.id])
    }

    /// adjustBalance (perform(), без публикации событий) — баланс в строке обязан обновляться БЕЗ
    /// рефреша снапшота: `state.accounts` хранит ту же @Model-ссылку, что и `modelContext`
    /// (единый контекст), поэтому `newCoreBalanceToday` пересчитывает по актуальным `.events`
    /// даже без `loadCoreEntities()`. Доказывает Fable-предположение №6 тестом, не пересказом.
    @Test("root-фикс: adjustBalance обновляет баланс в снапшоте без явного рефреша (живая @Model-ссылка)")
    func adjustBalanceReflectsLiveWithoutSnapshotRefresh() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Живой баланс", kind: .debitCard, currency: "RUB", openingBalance: 1_000)

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        let accountInSnapshot = try #require(vm.state.accounts.first)
        #expect(vm.newCoreBalanceToday(accountInSnapshot) == 1_000)

        // Мутируем ТУ ЖЕ @Model-ссылку через сервис на том же modelContext — намеренно НЕ вызываем
        // loadGroups/loadCoreEntities/EventBus.publish здесь: проверяем именно "без рефреша".
        _ = try coreService.adjustBalance(account: accountInSnapshot, to: 1_500)

        #expect(vm.newCoreBalanceToday(accountInSnapshot) == 1_500)
    }

    // MARK: - Миграция потребителя `FinanceGroupEditorView` (Ф5c.7.4, файл №2)

    /// `coreAccountsSnapshot(matching:)` — единая точка, которую теперь зовут И `FinanceRows`,
    /// И `accountsSection` в `FinanceGroupEditorView` — обязана показать core-счёт легаси-группы
    /// (ровно то, что увидит пользователь в редакторе группы).
    @Test("expand#2 FinanceGroupEditorView: coreAccountsSnapshot показывает core-счёт группы редактора")
    func coreAccountsSnapshotVisibleInGroupEditorScenario() throws {
        let ctx = try makeContext()
        let legacyGroup = FinanceGroup(name: "Ипотека", colorHex: "#444444", order: 0)
        ctx.insert(legacyGroup)
        let coreGroup = AccountGroup(name: "Ипотека")
        ctx.insert(coreGroup)

        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Счёт в редакторе", kind: .debitCard, currency: "RUB", openingBalance: 2_000, group: coreGroup)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        #expect(vm.coreAccountsSnapshot(matching: coreGroup).map(\.id) == [account.id])
    }

    /// Компаньон-фикс `.onDisappear { viewModel.handle(.loadGroups) }` на NavigationLink «Добавить
    /// счёт» в `FinanceGroupEditorView`: та же находка, что `.hideAddAccountSheet` у sheet-варианта —
    /// пуш-путь тоже не публикует событий, поэтому свежесозданный через push-флоу core-счёт обязан
    /// стать виден после `.loadGroups` (симулируем именно этот вызов, не сам SwiftUI-колбэк).
    @Test("expand#2: .loadGroups после push-CREATE делает core-счёт видимым в coreAccountsSnapshot редактора")
    func loadGroupsAfterPushedCreateRevealsAccountInEditorSnapshot() throws {
        let ctx = try makeContext()
        let legacyGroup = FinanceGroup(name: "Авто", colorHex: "#555555", order: 0)
        ctx.insert(legacyGroup)
        let coreGroup = AccountGroup(name: "Авто")
        ctx.insert(coreGroup)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)
        #expect(vm.coreAccountsSnapshot(matching: coreGroup).isEmpty)

        // Симулируем createMoneyAccountOnNewCore из пуш-флоу FinanceAddAccountView(.pushed) —
        // тот же путь, что и в sheet-варианте, событий не публикует.
        let coreService = AccountsCoreService(modelContext: ctx)
        let created = try coreService.createAccount(name: "Пуш-счёт", kind: .debitCard, currency: "RUB", openingBalance: 3_000, group: coreGroup)

        #expect(!vm.coreAccountsSnapshot(matching: coreGroup).map(\.id).contains(created.id)) // до рефреша ещё не видно

        vm.handle(.loadGroups) // как .onDisappear на NavigationLink в accountsSection

        #expect(vm.coreAccountsSnapshot(matching: coreGroup).map(\.id).contains(created.id))
    }

    // MARK: - Миграция потребителя `FinancesView` (Ф5c.7.4, файл №3)

    /// `FinancesView.isGroupEmpty` теперь зовёт `coreAccountsSnapshot(matching:)` вместо живого
    /// `newCoreAccounts(matching:)` — группа БЕЗ легаси-счетов, но С core-счётом (мост по имени),
    /// обязана считаться НЕ пустой (та же семантика, что раньше давал живой fetch).
    @Test("expand#3 FinancesView: группа без легаси-счетов, но с core-счётом — не пустая (coreAccountsSnapshot)")
    func groupWithOnlyCoreAccountIsNotEmptyViaSnapshot() throws {
        let ctx = try makeContext()
        let legacyGroup = FinanceGroup(name: "Только core", colorHex: "#666666", order: 0)
        ctx.insert(legacyGroup) // нет ни одного FinanceAccount-junction внутри — легаси-часть пуста
        let coreGroup = AccountGroup(name: "Только core")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        _ = try coreService.createAccount(name: "Core-счёт", kind: .debitCard, currency: "RUB", openingBalance: 100, group: coreGroup)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        // Реплика isGroupEmpty (FinancesView.swift) — легаси-часть пуста, core-часть — нет.
        #expect(vm.legacyAccountsMatchingGroupName(legacyGroup.name).isEmpty)
        #expect(!vm.coreAccountsSnapshot(matching: coreGroup).isEmpty)
    }

    // MARK: - Миграция потребителя `FinanceOverviewCardView` (Ф5c.7.4, файл №5)

    /// `buildLedgerPresentation` теперь зовёт `coreAccountsSnapshot(matching:)` вместо живого
    /// `newCoreAccounts(matching:)` в цикле по группам — core-счёт группы обязан попасть в ledger
    /// той же группы (та же семантика, что раньше давал живой fetch).
    @Test("expand#5 FinanceOverviewCardView: coreAccountsSnapshot отдаёт core-счёт группы для ledger-цикла")
    func coreAccountsSnapshotVisibleInLedgerGroupLoop() throws {
        let ctx = try makeContext()
        let legacyGroup = FinanceGroup(name: "Дашборд", colorHex: "#777777", order: 0)
        ctx.insert(legacyGroup)
        let coreGroup = AccountGroup(name: "Дашборд")
        ctx.insert(coreGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "В ledger", kind: .debitCard, currency: "RUB", openingBalance: 500, group: coreGroup)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        // Реплика цикла buildLedgerPresentation: `for group in state.groups { coreAccountsSnapshot(matching: group) }`.
        let groupInList = try #require(vm.state.groups.first(where: { $0.name == "Дашборд" }))
        #expect(vm.coreAccountsSnapshot(matching: groupInList).map(\.id) == [account.id])
    }

    /// `reloadToken` (FinanceOverviewCardView) строит дешёвый прокси-хеш из `events.count`/
    /// `archivedAt`/`group?.id` core-счетов — без core-части токен «слеп» к core-мутациям
    /// (adjustBalance/archiveAccount/updateAccount(группа) не публикуют легаси-события). Тест
    /// реплицирует формулу токена и доказывает, что каждая мутация меняет строку — регресс-guard
    /// на саму идею прокси, не на приватное свойство View (недоступно из теста).
    @Test("expand#5: прокси-компоненты reloadToken (events.count/archivedAt/group) меняются при core-мутациях")
    func reloadTokenCoreProxyChangesOnMutations() throws {
        let ctx = try makeContext()
        let groupA = AccountGroup(name: "А")
        let groupB = AccountGroup(name: "Б")
        ctx.insert(groupA); ctx.insert(groupB)
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Прокси", kind: .debitCard, currency: "RUB", openingBalance: 1_000, group: groupA)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        func tokenPart(_ acc: Account) -> String {
            "\(acc.id)_\(acc.name)_\(acc.events?.count ?? 0)_\(acc.archivedAt?.timeIntervalSince1970 ?? 0)_\(acc.group?.id.uuidString ?? "nil")"
        }

        let before = tokenPart(account)

        _ = try coreService.adjustBalance(account: account, to: 1_500)
        let afterBalance = tokenPart(account)
        #expect(before != afterBalance) // events.count вырос

        try coreService.archiveAccount(account)
        let afterArchive = tokenPart(account)
        #expect(afterBalance != afterArchive) // archivedAt заполнился

        try coreService.restoreAccount(account)
        let afterRestore = tokenPart(account)
        #expect(afterArchive != afterRestore) // archivedAt снова nil

        // Fable-находка: rename БЕЗ смены группы — updateAccount мутирует name напрямую
        // (AccountsCoreService.swift:496-498), а accountName рендерится в ledger (:320).
        _ = try coreService.updateAccount(account, name: "Переименован", group: groupA)
        let afterRename = tokenPart(account)
        #expect(afterRestore != afterRename) // name сменился, группа та же

        _ = try coreService.updateAccount(account, name: account.name, group: groupB)
        let afterGroupChange = tokenPart(account)
        #expect(afterRename != afterGroupChange) // group?.id сменился
    }

    // MARK: - Core-aware Ungrouped фикс (Fable-находка, `FinanceViewModel.loadGroups`)

    /// (а) [Ф5c.7 contract, портировано] core-only Ungrouped: НЕТ ни одного легаси-счёта в системе,
    /// но ЕСТЬ core-счёт с `group == nil`. Канон Ungrouped = `group == nil`, НЕ сущность — `state.groups`
    /// СТРУКТУРНО исключает Ungrouped-имя (было: легаси-Ungrouped-группа оставалась видна в
    /// `state.groups` через смешанный легаси/core фильтр). Счёт доступен через `ungroupedAccounts()`.
    @Test("Ungrouped-фикс (а): core-only Ungrouped НЕ в state.groups (канон), виден через ungroupedAccounts()")
    func coreOnlyUngroupedGroupStaysVisibleAndLedgerSeesAccount() throws {
        let ctx = try makeContext()
        let coreService = AccountsCoreService(modelContext: ctx)
        let account = try coreService.createAccount(name: "Core без группы", kind: .debitCard, currency: "RUB", openingBalance: 777, group: nil)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        #expect(!vm.state.groups.map(\.name).contains(FinanceSystemGroups.ungroupedName))
        #expect(vm.ungroupedAccounts().map(\.id) == [account.id])
    }

    /// (б) оба мира пусты — Ungrouped обязана оставаться скрытой (регресс-guard старого поведения,
    /// дублирует семантику `FinanceViewModelCharacterizationTests.visibleGroupsHidesEmptyUngrouped`,
    /// но уже через `state.groups` напрямую, не через `visibleGroupsForList()`).
    @Test("Ungrouped-фикс (б): легаси И core пусты — Ungrouped скрыта в state.groups")
    func bothEmptyUngroupedStaysHidden() throws {
        let ctx = try makeContext()
        let ungrouped = FinanceGroup(name: FinanceSystemGroups.ungroupedName, colorHex: FinanceSystemGroups.ungroupedColorHex, order: 0)
        ctx.insert(ungrouped)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        #expect(!vm.state.groups.map(\.name).contains(FinanceSystemGroups.ungroupedName))
    }

    /// (г) [Ф5c.7 contract, портировано] анти-дубль: `state.groups` НЕ содержит Ungrouped вообще
    /// (структурно, канон `group == nil`, не сущность) — 0 совпадений по имени, не «не более одного
    /// раза». Счёт без группы встречается РОВНО один раз — в `ungroupedAccounts()`, не задвоен ни в
    /// одной именной группе (grep подтвердил: `FinancesView`/`FinanceOverviewCardView` — Ungrouped
    /// отдельным блоком, не через `FinanceGroupRow`/`coreAccountsSnapshot` цикл по именным группам).
    @Test("Ungrouped-фикс (г): анти-дубль — Ungrouped НЕ в state.groups, счёт без группы виден 1 раз через ungroupedAccounts()")
    func exactlyOneUngroupedBucketNoDuplicateRender() throws {
        let ctx = try makeContext()
        let namedGroup = AccountGroup(name: "Именная", order: 1)
        ctx.insert(namedGroup)
        let coreService = AccountsCoreService(modelContext: ctx)
        let ungroupedAccount = try coreService.createAccount(name: "Без группы", kind: .debitCard, currency: "RUB", openingBalance: 300, group: nil)
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.handle(.loadGroups)

        // Ungrouped структурно отсутствует в state.groups (0, не "не более одного").
        let ungroupedMatches = vm.state.groups.filter { $0.name == FinanceSystemGroups.ungroupedName }
        #expect(ungroupedMatches.isEmpty)

        // Счёт без группы НЕ задвоен ни в одной именной группе (coreAccountsSnapshot по каждой),
        // и встречается РОВНО один раз в ungroupedAccounts().
        var occurrencesInNamedGroups = 0
        for group in vm.state.groups {
            occurrencesInNamedGroups += vm.coreAccountsSnapshot(matching: group).filter { $0.id == ungroupedAccount.id }.count
        }
        #expect(occurrencesInNamedGroups == 0)
        #expect(vm.ungroupedAccounts().filter { $0.id == ungroupedAccount.id }.count == 1)
    }
}
