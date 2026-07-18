import Foundation
import SwiftData
import Testing
@testable import millio

/// 6b Фаза 2b (single-world): `ChartDataPoint.mergingNewCoreSeries` (dual-path — отдельный
/// дневной ряд ядра + forward-fill приближённое слияние с легаси-скелетом) снесён. Замена —
/// `FinanceDynamicsViewModel.addingCoreContribution` — точный запрос ядра НА ТЕ ЖЕ даты, что уже
/// построил легаси-скелет (`buildTimeSeriesData`). Тесты здесь проверяют результирующее поведение
/// агрегированного графика «Динамики» через публичный `updateChartDataAsync()`, а не саму
/// (приватную) функцию — тестируем контракт, а не реализацию.
@Suite("Dynamics aggregated chart: core contribution (6b Фаза 2b, замена mergingNewCoreSeries)")
@MainActor
struct FinanceDynamicsCoreContributionTests {

    private static var retainedContainers: [ModelContainer] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        return container.mainContext
    }

    private func makeMigrator(modelContext: ModelContext, nowProvider: @escaping () -> Date) -> LegacyAccountsMigrator {
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "core-series-reg-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "core-series-flag-\(UUID().uuidString)")!
        return LegacyAccountsMigrator(modelContext: modelContext, registry: registry, defaults: flagDefaults, nowProvider: nowProvider)
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        intervalNanoseconds: UInt64 = 10_000_000,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let start = DispatchTime.now().uptimeNanoseconds
        while DispatchTime.now().uptimeNanoseconds - start < timeoutNanoseconds {
            await Task.yield()
            if condition() { return }
            try? await Task.sleep(nanoseconds: intervalNanoseconds)
        }
    }

    // MARK: - Мигрированный легаси-счёт: скелет истории + вклад ядра после миграции

    @Test("Мигрированный счёт: доскелетная легаси-история сохраняется, текущее значение приходит от ядра (не 0)")
    func migratedAccount_preservesLegacyHistoryAndCarriesCoreValueForward() async throws {
        let ctx = try makeContext()
        let now = Date()
        // Миграция — час назад (строго раньше любого последующего "now" в этом тесте), создание
        // счёта — 10 дней назад. Фиксированный nowProvider у мигратора делает archivedAt/opening-
        // событие ядра детерминированными, без гонки с реальным Date().
        let migratedAt = now.addingTimeInterval(-3_600)
        let createdAt = now.addingTimeInterval(-10 * 86_400)

        let card = Card(
            name: "Легаси карта",
            cardNumber: "1234",
            cardType: .debit,
            currency: "RUB",
            balance: 100_000
        )
        card.createdAt = createdAt
        card.updatedAt = migratedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        // Мигрируем ДО построения VM — легаси скрыт (archivedAt=migratedAt), core-двойник создан
        // с opening-событием на migratedAt.
        let migrator = makeMigrator(modelContext: ctx, nowProvider: { migratedAt })
        let summary = migrator.migrateAll()
        #expect(summary.migrated == 1)
        #expect(card.archivedAt == migratedAt)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx,
            financeViewModel: financeViewModel,
            currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.period = .month
        dynamicsViewModel.state.dynamicsMode = .aggregated
        await dynamicsViewModel.updateChartDataAsync()

        let points = dynamicsViewModel.state.chartData.sorted { $0.date < $1.date }
        #expect(!points.isEmpty, "Легаси-скелет должен построиться (счёт существовал, есть junction)")

        // Точка на конце периода ("сейчас", ПОСЛЕ миграции) — легаси скрыт (вносит 0), но core-
        // двойник вносит мигрированный баланс. Если бы вклад ядра не добавлялся (регресс к
        // dual-path без core, или к простому обнулению), здесь было бы 0.
        let lastValue = try #require(points.last?.value)
        #expect(abs(lastValue - 100_000) < 0.01, "Текущая точка должна прийти от ядра (100 000), а не обнулиться вместе с легаси")

        // Q2 (dynamics-single-source-of-truth): период .month держит запрошенную ширину, поэтому
        // точки до создания счёта (createdAt = -10 дней) считаются нулём. После создания —
        // легаси-история (до миграции) и core-двойник (после) несут 100 000; история не обнулена.
        let afterCreation = points.filter { $0.date >= createdAt }
        #expect(
            afterCreation.allSatisfy { abs($0.value - 100_000) < 0.01 },
            "После создания счёта серия несёт легаси/core-значение 100 000 на всех точках"
        )
        #expect(
            points.contains { abs($0.value - 100_000) < 0.01 },
            "Легаси-история (100 000) присутствует в серии, а не обнулена новым механизмом"
        )
    }

    // MARK: - Нет core-счетов вообще: скелет не меняется (не регресс, известный пробел «1b»)

    @Test("Нет core-счетов — агрегированный график строится только по легаси, как раньше (не регрессия)")
    func noCoreAccounts_chartUnaffectedByCoreContributionStep() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-5 * 86_400)

        let card = Card(name: "Обычная карта", cardNumber: "5555", cardType: .debit, currency: "RUB", balance: 50_000)
        card.createdAt = createdAt
        card.updatedAt = now
        card.initialBalance = 50_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        // Миграция НЕ запускается — ядро (`Account`) пусто, хотя тип зарегистрирован в схеме.
        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx,
            financeViewModel: financeViewModel,
            currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.period = .month
        dynamicsViewModel.state.dynamicsMode = .aggregated
        await dynamicsViewModel.updateChartDataAsync()

        let points = dynamicsViewModel.state.chartData.sorted { $0.date < $1.date }
        #expect(!points.isEmpty)
        // Без core-счетов продюсер добавляет 0 — серия равна чистому легаси-скелету. Q2: клэмп базы
        // снят, поэтому точки до createdAt = 0, а с момента создания счёта — живой баланс 50 000.
        for point in points {
            let isZero = abs(point.value) < 0.01
            let isBalance = abs(point.value - 50_000) < 0.01
            #expect(isZero || isBalance, "Точка равна 0 (до создания счёта) либо чистому легаси-балансу 50 000")
        }
        #expect(abs((points.last?.value ?? 0) - 50_000) < 0.01, "Конец периода = живой баланс 50 000")
        #expect(points.contains { abs($0.value - 50_000) < 0.01 }, "После создания счёта серия несёт 50 000")
    }

    // MARK: - Ветка .accounts: только core-счета (Фаза 6b, баг «No products»)

    @Test("Вкладка «Счета»: при пустых легаси-таблицах core-счёт даёт непустой breakdown (не «No products»)")
    func accountsBreakdown_includesCoreAccountsWhenLegacyEmpty() async throws {
        let ctx = try makeContext()
        let createdAt = Date().addingTimeInterval(-60 * 86_400)

        // Легаси-группа и мирронная AccountGroup — одно имя (мост по имени, newCoreAccounts(matching:)).
        let financeGroup = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(financeGroup)
        let coreGroup = AccountGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(coreGroup)

        // Чистый core-счёт с балансом. Легаси-счетов (FinanceAccount) НЕ создаём — эмулируем состояние
        // после Ф1–Ф5b, когда легаси-таблицы пусты.
        let accountsService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try accountsService.createAccount(
            name: "Наличные",
            kind: .cash,
            currency: "RUB",
            openingBalance: 200_000,
            group: coreGroup,
            date: createdAt
        )
        _ = coreAccount
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx,
            financeViewModel: financeViewModel,
            currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.period = .month
        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()

        let breakdown = dynamicsViewModel.state.dynamicsBreakdown
        #expect(!breakdown.isEmpty, "Ветка .accounts должна показать core-счёт, а не пустой список (баг «No products»)")
        let core = try #require(breakdown.first { $0.name == "Наличные" })
        #expect(abs(core.endValue - 200_000) < 0.01, "Баланс core-счёта должен прийти от accountsTotalsService (200 000)")
    }

    // MARK: - Start строки core-счёта: домиграционный баланс от легаси-предшественника (не 0)

    @Test("Мигрированный счёт на вкладке «Счета»: Start строки = легаси-баланс до миграции (не 0), Total согласован с графиком")
    func migratedAccount_rowStartUsesLegacyPredecessor_andTotalMatchesChart() async throws {
        let ctx = try makeContext()
        let now = Date()
        // Счёт создан 20 дней назад, миграция 6b — 5 дней назад. Период начинается 10 дней назад:
        // строго ПОСЛЕ создания и ДО миграции — точь-в-точь сценарий владельца (период через границу
        // миграции). До фикса core.total(start)=0 → Start строки и Total=0 при живом графике.
        let createdAt = now.addingTimeInterval(-20 * 86_400)
        let migratedAt = now.addingTimeInterval(-5 * 86_400)

        let card = Card(name: "Легаси карта", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = migratedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        // Мигратор пишет в `.shared` — тот же реестр, что читает VM (reverse-lookup); чистим в defer.
        let legacyUniqueID = card.cardUniqueID
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: legacyUniqueID) }
        let flagDefaults = UserDefaults(suiteName: "core-predecessor-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(
            modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt }
        )
        #expect(migrator.migrateAll().migrated == 1)
        #expect(LegacyConversionRegistry.shared.coreAccountID(forLegacyUniqueID: legacyUniqueID) != nil)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        // Явный период через границу миграции (start после создания, до миграции).
        dynamicsViewModel.state.customPeriod = (start: now.addingTimeInterval(-10 * 86_400), end: now)
        dynamicsViewModel.state.dynamicsMode = .aggregated
        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()

        let breakdown = dynamicsViewModel.state.dynamicsBreakdown
        let row = try #require(breakdown.first { $0.name == "Легаси карта" }, "core-строка должна быть в breakdown")
        // Start строки = легаси-баланс на начало периода (100 000), а НЕ 0 (баг «+∞»/«показывает 0»).
        #expect(abs(row.startValue - 100_000) < 0.01, "Start строки должен взять баланс легаси-предшественника до миграции (100 000), не 0")
        #expect(abs(row.endValue - 100_000) < 0.01, "End строки приходит от ядра после миграции (100 000)")

        // Total (сумма строк) согласован с первой точкой серии графика — требование владельца.
        let total = try #require(FinanceDynamicsPresentation.totalRow(from: breakdown, viewMode: .accounts))
        await dynamicsViewModel.updateChartDataAsync()
        let firstPoint = try #require(dynamicsViewModel.state.chartData.sorted { $0.date < $1.date }.first)
        #expect(abs(total.startValue - firstPoint.value) < 0.01, "Total Start должен совпасть с первой точкой графика (\(firstPoint.value)), а не быть 0")
    }

    // MARK: - Ветка .groups: Start строки группы = домиграционный баланс легаси-предшественника (не 0)

    @Test("Мигрированный счёт на вкладке «Группы»: Start строки группы = легаси-баланс до миграции (не 0)")
    func migratedGroupRow_startUsesLegacyPredecessor() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-20 * 86_400)
        let migratedAt = now.addingTimeInterval(-5 * 86_400)

        let card = Card(name: "Легаси карта", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = migratedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)

        let group = FinanceGroup(name: "Основная", colorHex: "#FFFFFF")
        ctx.insert(group)
        let account = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        account.group = group
        group.accounts = [account]
        ctx.insert(account)
        try ctx.save()

        let legacyUniqueID = card.cardUniqueID
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: legacyUniqueID) }
        let flagDefaults = UserDefaults(suiteName: "core-group-pred-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(
            modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt }
        )
        #expect(migrator.migrateAll().migrated == 1)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.customPeriod = (start: now.addingTimeInterval(-10 * 86_400), end: now)
        dynamicsViewModel.state.dynamicsMode = .aggregated
        dynamicsViewModel.state.viewMode = .groups
        await dynamicsViewModel.updateDynamicsBreakdown()

        let breakdown = dynamicsViewModel.state.dynamicsBreakdown
        let row = try #require(breakdown.first { $0.name == "Основная" }, "строка группы должна быть в breakdown")
        // Start строки группы = легаси-баланс на начало периода (100 000), а НЕ 0 (симптом «у групп нет начала»).
        #expect(abs(row.startValue - 100_000) < 0.01, "Start строки группы должен взять баланс легаси-предшественника core-счёта (100 000), не 0")
        #expect(abs(row.endValue - 100_000) < 0.01, "End строки группы приходит от ядра после миграции (100 000)")
    }

    // MARK: - Ветка .groups: счета без группы попадают отдельной Ungrouped-строкой (паритет с «Счета»)

    @Test("Вкладка «Группы»: core-счёт без группы показывается отдельной Ungrouped-строкой (паритет Total с «Счета»)")
    func ungroupedCoreAccount_appearsAsUngroupedRowInGroupsBreakdown() async throws {
        let ctx = try makeContext()
        let createdAt = Date().addingTimeInterval(-60 * 86_400)

        // Чистый core-счёт БЕЗ группы (group == nil) — эмулирует состояние после 6b, когда легаси пуста.
        let accountsService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try accountsService.createAccount(
            name: "Наличные без группы",
            kind: .cash,
            currency: "RUB",
            openingBalance: 150_000,
            group: nil,
            date: createdAt
        )
        _ = coreAccount
        try ctx.save()

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(
            modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService()
        )
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.period = .month

        // Groups: ungrouped-счёт должен присутствовать отдельной строкой, иначе Total групп занижен.
        dynamicsViewModel.state.viewMode = .groups
        await dynamicsViewModel.updateDynamicsBreakdown()
        let groupsBreakdown = dynamicsViewModel.state.dynamicsBreakdown
        let ungroupedRow = try #require(
            groupsBreakdown.first { $0.name == FinanceSystemGroups.ungroupedName },
            "core-счёт без группы должен попасть в Ungrouped-строку вкладки «Группы» (раньше выпадал → Total=0)"
        )
        #expect(abs(ungroupedRow.endValue - 150_000) < 0.01, "End Ungrouped-строки = баланс core-счёта без группы (150 000)")

        let groupsTotal = try #require(FinanceDynamicsPresentation.totalRow(from: groupsBreakdown, viewMode: .groups))

        // Accounts: тот же счёт виден per-account; Total обеих вкладок должен сойтись.
        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()
        let accountsBreakdown = dynamicsViewModel.state.dynamicsBreakdown
        let accountsTotal = try #require(FinanceDynamicsPresentation.totalRow(from: accountsBreakdown, viewMode: .accounts))
        #expect(abs(groupsTotal.endValue - accountsTotal.endValue) < 0.01,
                "Total вкладок «Группы» и «Счета» должен совпадать после включения Ungrouped-строки")
    }

    // MARK: - Инвариант единого источника: Total(Groups) == Total(Accounts) на смешанной фикстуре

    @Test("Единый источник: Total вкладок «Группы» и «Счета» совпадает (2 группы + ungrouped + мигрированный + кредит), Ungrouped ровно одна строка")
    func groupsAndAccountsTotalsMatch_onMixedFixture() async throws {
        let ctx = try makeContext()
        let now = Date()
        let createdAt = now.addingTimeInterval(-40 * 86_400)
        let migratedAt = now.addingTimeInterval(-5 * 86_400)

        // Легаси-FinanceGroup для state.groups + одноимённые AccountGroup для core-счетов (матч по имени).
        let financeGroupA = FinanceGroup(name: "Группа A", colorHex: "#111111")
        let financeGroupB = FinanceGroup(name: "Группа B", colorHex: "#222222")
        ctx.insert(financeGroupA)
        ctx.insert(financeGroupB)
        let coreGroupA = AccountGroup(name: "Группа A")
        let coreGroupB = AccountGroup(name: "Группа B")
        ctx.insert(coreGroupA)
        ctx.insert(coreGroupB)

        let accountsService = AccountsCoreService(modelContext: ctx)
        // Группа A: актив + обязательство (кредит с отрицательным итогом) — проверяет знаковую агрегацию.
        _ = try accountsService.createAccount(name: "Наличные A", kind: .cash, currency: "RUB", openingBalance: 200_000, group: coreGroupA, date: createdAt)
        _ = try accountsService.createAccount(name: "Кредит A", kind: .loan, currency: "RUB", openingBalance: 500_000, group: coreGroupA, date: createdAt)
        // Группа B: актив.
        _ = try accountsService.createAccount(name: "Наличные B", kind: .cash, currency: "RUB", openingBalance: 300_000, group: coreGroupB, date: createdAt)
        // Ungrouped: core без группы.
        _ = try accountsService.createAccount(name: "Наличные без группы", kind: .cash, currency: "RUB", openingBalance: 150_000, group: nil, date: createdAt)

        // Мигрированный легаси-счёт (в Группе B): проверяет путь легаси-предшественника.
        let card = Card(name: "Легаси карта B", cardNumber: "9999", cardType: .debit, currency: "RUB", balance: 100_000)
        card.createdAt = createdAt
        card.updatedAt = migratedAt
        card.initialBalance = 100_000
        card.hasInitialBalance = true
        ctx.insert(card)
        let legacyAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        legacyAccount.group = financeGroupB
        financeGroupB.accounts = [legacyAccount]
        ctx.insert(legacyAccount)
        try ctx.save()

        let legacyUniqueID = card.cardUniqueID
        defer { LegacyConversionRegistry.shared.remove(legacyUniqueID: legacyUniqueID) }
        let flagDefaults = UserDefaults(suiteName: "one-source-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: .shared, defaults: flagDefaults, nowProvider: { migratedAt })
        #expect(migrator.migrateAll().migrated == 1)

        let financeViewModel = FinanceViewModel(modelContext: ctx, currencyService: MockCurrencyRateService(), skipInitialLoad: true)
        financeViewModel.handle(.loadGroups)
        financeViewModel.handle(.loadAccounts)

        let dynamicsViewModel = FinanceDynamicsViewModel(modelContext: ctx, financeViewModel: financeViewModel, currencyService: MockCurrencyRateService())
        dynamicsViewModel.handle(.loadData)
        await waitUntil { !dynamicsViewModel.state.isLoading }
        dynamicsViewModel.state.period = .month

        dynamicsViewModel.state.viewMode = .groups
        await dynamicsViewModel.updateDynamicsBreakdown()
        let groupsBreakdown = dynamicsViewModel.state.dynamicsBreakdown
        let groupsTotal = try #require(FinanceDynamicsPresentation.totalRow(from: groupsBreakdown, viewMode: .groups))

        // Ungrouped-строка ровно одна (регресс тройного Ungrouped: раньше псевдогруппа + синтетика двоили).
        let ungroupedRows = groupsBreakdown.filter { $0.name == FinanceSystemGroups.ungroupedName }
        #expect(ungroupedRows.count == 1, "Ungrouped должна быть ровно одна строка, а не дубли (баг тройного Ungrouped)")

        dynamicsViewModel.state.viewMode = .accounts
        await dynamicsViewModel.updateDynamicsBreakdown()
        let accountsBreakdown = dynamicsViewModel.state.dynamicsBreakdown
        let accountsTotal = try #require(FinanceDynamicsPresentation.totalRow(from: accountsBreakdown, viewMode: .accounts))

        // Инвариант единого источника: обе вкладки агрегируют ОДНИ И ТЕ ЖЕ per-account строки.
        #expect(abs(groupsTotal.startValue - accountsTotal.startValue) < 0.01,
                "Start Total(Groups)=\(groupsTotal.startValue) должен совпасть с Total(Accounts)=\(accountsTotal.startValue)")
        #expect(abs(groupsTotal.endValue - accountsTotal.endValue) < 0.01,
                "End Total(Groups)=\(groupsTotal.endValue) должен совпасть с Total(Accounts)=\(accountsTotal.endValue)")
    }
}
