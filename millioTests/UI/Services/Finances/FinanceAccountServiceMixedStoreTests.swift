import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф5c.7.2 — гейт-тесты `FinanceAccountService` как ЛЕГАСИ-fallback-узла (инварианты 5 и 6 плана).
///
/// Контекст решения (журнал плана 5c.7.2): тип-флип публичного API этого сервиса на `Account`/
/// `AccountGroup` отложен на 5c.7.3 (каскадит в легаси-typed вызывающих), а core-путь архива/restore/
/// delete уже существует отдельно (`AccountDetailView:846`, `ArchivedAccountsView:133/144`) — маршрут
/// сюда был бы мёртвым кодом + дублем. Поэтому 5c.7.2 не портирует, а ФИКСИРУЕТ тестами, что:
///   1) `loadAccounts()` продолжает наполнять `CardCatalog`/`CardManager` — источники пикеров
///      Cashflow/Cashback (`CashflowViewModel:423`), инвариант 6 §2.1;
///   2) легаси archive/restore-путь остаётся зелёным на СМЕШАННОМ сторе (converted core-счёт +
///      непроконвертированная легаси-запись одновременно), не задевая core-двойник, инвариант 5 §2.1.
@MainActor
struct FinanceAccountServiceMixedStoreTests {

    private func makeContext() throws -> (container: ModelContainer, context: ModelContext) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        return (container, container.mainContext)
    }

    /// Провайдеры читают из стора динамически — как VM после `onLoad*`. Колбэки — no-op:
    /// тестируем чистый эффект сервиса на store, без обратной связи в VM.
    private func makeService(_ ctx: ModelContext) -> FinanceAccountService {
        FinanceAccountService(
            modelContext: ctx,
            ungroupedGroupName: FinanceSystemGroups.ungroupedName,
            groupsProvider: {
                (try? ctx.fetch(FetchDescriptor<FinanceGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []
            },
            nextOrderProvider: { _ in 0 },
            onAccountsLoaded: { _ in },
            onCachesRebuilt: { _ in },
            onLoadAccounts: {},
            onLoadGroups: {},
            onUpdateUnattachedItems: {},
            onCalculateTotal: {},
            onScheduleGroupTotalRefresh: { _ in },
            onDismissAddAccountSheet: {}
        )
    }

    // MARK: - Smoke: CardCatalog/CardManager populate (инвариант 6)

    @Test("loadAccounts наполняет CardCatalog/CardManager — пикеры Cashflow/Cashback не пустые")
    func loadAccountsPopulatesCardPickers() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let card = Card(name: "Карта", cardNumber: "1234", cardType: .debit, currency: "RUB", balance: 5_000)
        ctx.insert(card)
        try ctx.save()

        let service = makeService(ctx)
        service.loadAccounts()

        // Прямой источник пикера Cashflow (`CashflowViewModel:423`) — context-scoped, без синглтона.
        let catalog = CardCatalog.fetchAll(in: ctx)
        #expect(catalog.contains { $0.cardUniqueID == card.cardUniqueID })

        // `CardManager.shared` наполняется через `loadAccounts()`→`setup(modelContext:)`. Тело теста
        // синхронно и на MainActor — между loadAccounts и ассертом другой тест вклиниться не может,
        // значение детерминировано. Если будущая правка оборвёт `setup` в loadAccounts — getAllCards
        // вернёт stale/[] и тест покраснеет (ловит Fable-риск №7).
        let managed = CardManager.shared.getAllCards()
        #expect(managed.contains { $0.cardUniqueID == card.cardUniqueID })
    }

    // MARK: - Mixed store: легаси archive/restore (инвариант 5)

    @Test("Смешанный стор: легаси archive/restore на непроконвертированной записи, core-двойник не тронут")
    func mixedStoreLegacyArchiveRestoreLeavesCoreUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container

        // (1) Конвертированный core-счёт — эмулирует мигрированный двойник (двоемирие до 5c.11).
        let coreService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try coreService.createAccount(
            name: "Core-счёт", kind: .debitCard, currency: "RUB", openingBalance: 10_000
        )

        // (2) Непроконвертированная легаси-запись + junction в группе — эмулирует leftover, который
        // обязан продолжать работать до физического сноса @Model (5c.11), инвариант 5 §2.1.
        let group = FinanceGroup(name: "Карты", colorHex: "#111111", order: 0)
        ctx.insert(group)
        let legacyCard = Card(name: "Легаси карта", cardNumber: "9999", cardType: .debit, currency: "RUB", balance: 3_000)
        ctx.insert(legacyCard)
        let junction = FinanceAccount(accountType: .card, accountID: legacyCard.cardUniqueID)
        junction.group = group
        ctx.insert(junction)
        try ctx.save()

        let service = makeService(ctx)
        // Загрузка на смешанном сторе не должна падать/терять легаси-карту из пикера.
        service.loadAccounts()
        #expect(CardCatalog.fetchAll(in: ctx).contains { $0.cardUniqueID == legacyCard.cardUniqueID })

        // Легаси archive (removeAccountFromGroup) прячет ТОЛЬКО легаси-карту.
        let kind = service.removeAccountFromGroup(junction)
        #expect(kind == .card)
        #expect(legacyCard.archivedAt != nil)
        #expect(coreAccount.archivedAt == nil) // core-двойник не тронут легаси-путём

        // Легаси restore возвращает карту в группу, core по-прежнему не тронут.
        service.restoreArchivedAccountToGroup(accountType: .card, accountID: legacyCard.cardUniqueID, group: group)
        #expect(legacyCard.archivedAt == nil)
        #expect(coreAccount.archivedAt == nil)

        // Junction восстановлен в ту же группу (order-провайдер вернул 0).
        let junctions = try ctx.fetch(FetchDescriptor<FinanceAccount>())
        #expect(junctions.contains { $0.accountID == legacyCard.cardUniqueID && $0.group?.groupUniqueID == group.groupUniqueID })
    }

    // MARK: - Регрессия Ф7: тоггл includeInTotal кредита переживает загрузку

    /// Ф7-регрессия: `loadAccounts()` больше НЕ форсит `Credit.includeInTotal = true`
    /// (снесён `normalizeCreditsIncludeInTotal`). Раньше пользовательский тоггл «не учитывать
    /// кредит в тотале» молча возвращался в true на каждой загрузке финансов.
    @Test("Ф7: includeInTotal=false у кредита переживает loadAccounts (normalize снесён)")
    func creditIncludeInTotalFalseSurvivesLoad() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let credit = Credit(
            name: "Кредит вне тотала",
            amount: 100_000,
            interestRate: 0,
            monthlyPayment: 5_000,
            startDate: Date(),
            termMonths: 12,
            currency: "RUB",
            includeInTotal: false
        )
        ctx.insert(credit)
        try ctx.save()
        let creditID = credit.creditUniqueID

        let service = makeService(ctx)
        service.loadAccounts()

        let reloaded = try ctx.fetch(FetchDescriptor<Credit>())
            .first { $0.creditUniqueID == creditID }
        #expect(reloaded?.includeInTotal == false)
    }

    @Test("Смешанный стор: физическое удаление легаси-записи не задевает core-двойник")
    func mixedStorePhysicalDeleteLeavesCoreUntouched() throws {
        let (container, ctx) = try makeContext()
        _ = container

        let coreService = AccountsCoreService(modelContext: ctx)
        let coreAccount = try coreService.createAccount(
            name: "Core-счёт", kind: .debitCard, currency: "RUB", openingBalance: 10_000
        )
        let coreID = coreAccount.id

        let group = FinanceGroup(name: "Карты", colorHex: "#111111", order: 0)
        ctx.insert(group)
        let legacyCard = Card(name: "Легаси карта", cardNumber: "9999", cardType: .debit, currency: "RUB", balance: 3_000)
        ctx.insert(legacyCard)
        let legacyID = legacyCard.cardUniqueID
        let junction = FinanceAccount(accountType: .card, accountID: legacyID)
        junction.group = group
        ctx.insert(junction)
        try ctx.save()

        let service = makeService(ctx)
        service.loadAccounts()

        let result = service.physicallyDeleteLegacyAccount(junction)
        #expect(result.kind == .card)

        // Легаси-карта и junction физически удалены.
        let remainingCards = try ctx.fetch(FetchDescriptor<Card>())
        #expect(!remainingCards.contains { $0.cardUniqueID == legacyID })
        let remainingJunctions = try ctx.fetch(FetchDescriptor<FinanceAccount>())
        #expect(!remainingJunctions.contains { $0.accountID == legacyID })

        // Core-двойник цел.
        let remainingCore = try ctx.fetch(FetchDescriptor<Account>())
        #expect(remainingCore.contains { $0.id == coreID })
    }
}
