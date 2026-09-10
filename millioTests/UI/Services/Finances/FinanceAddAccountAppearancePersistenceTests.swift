import Foundation
import SwiftData
import Testing
@testable import millio

/// Баг 2: тумблеры «избранное»/иконка/цвет были в формах, но `FinanceProductCreationInput` их
/// не несло — оформление молча терялось при создании ЛЮБОГО типа счёта.
///
/// Первый круг фикса покрывал только `AccountAppearancePersister`, вызванный ВРУЧНУЮ рядом с
/// фабрикой — это не ловило регрессию, если саму точку вызова убрать из реального пути создания
/// (`FinanceAddAccountView+CoreCreate.swift`). Второй круг вынес тело каждого `create*OnNewCore`
/// в `AccountCreationCoordinator` (см. его doc-комментарий — `@State` вне живого рендера SwiftUI
/// не читается обратно, поэтому вызвать сам `View`-метод в unit-тесте нельзя). Тесты ниже зовут
/// РЕАЛЬНЫЕ функции координатора — те же, что вызывает `CoreCreate.swift`: удаление вызова
/// `AccountAppearancePersister.persistIfNeeded` внутри любой из них ломает соответствующий тест.
@Suite(.serialized)
@MainActor
struct FinanceAddAccountAppearancePersistenceTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func createdAccountID(named name: String, in context: ModelContext) throws -> UUID {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == name })
        return try #require(try context.fetch(descriptor).first).id
    }

    // MARK: - Ядро: no-op при пустом наборе, upsert при непустом, коммит контекста

    @Test("Все три пустые/false — строка в сторе не создаётся (не плодим мусор)")
    func emptyDraftIsNoOp() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: false, iconName: nil, tintHex: nil)

        #expect(try AccountAppearanceStore(context: ctx).appearance(for: accountID) == nil)
    }

    @Test("Только isFavorite=true — строка создаётся, а не остаётся молчаливо пустой (сам Баг 2)")
    func favoriteOnlyPersists() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: true, iconName: nil, tintHex: nil)

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == nil)
        #expect(appearance.tintHex == nil)
    }

    @Test("Только иконка (без избранного) — строка создаётся")
    func iconOnlyPersists() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: false, iconName: "star.fill", tintHex: nil)

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == false)
        #expect(appearance.iconName == "star.fill")
    }

    @Test("Избранное+иконка+цвет — все три поля доходят до стора одним upsert'ом")
    func fullDraftPersistsAllFields() throws {
        let ctx = try makeContext()
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(context: ctx, accountID: accountID, isFavorite: true, iconName: "banknote", tintHex: "#FF00FF")

        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: accountID))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == "banknote")
        #expect(appearance.tintHex == "#FF00FF")
    }

    /// Баг 3: `upsert` только вставляет в контекст — сам НЕ коммитит, в отличие от соседних
    /// `FinanceViewModel.saveAppearance`/`toggleFavorite`. Тест из `ctx.fetch` СРАЗУ после вставки
    /// (как в тестах выше) не ловит это: SwiftData отдаёт из ТОГО ЖЕ контекста несохранённые
    /// объекты как есть. Читаем из ВТОРОГО контекста того же контейнера — он видит только то, что
    /// реально закоммичено, ровно как relaunch приложения (новый `ModelContext` на старте).
    @Test("Оформление переживает новый ModelContext того же контейнера — persistIfNeeded коммитит, не только вставляет")
    func appearanceSurvivesFreshContextOnSameContainer() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        let accountID = UUID()

        AccountAppearancePersister.persistIfNeeded(
            context: container.mainContext, accountID: accountID, isFavorite: true, iconName: "star.fill", tintHex: nil
        )

        let freshContext = ModelContext(container)
        let appearance = try #require(try AccountAppearanceStore(context: freshContext).appearance(for: accountID))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == "star.fill")
    }

    // MARK: - Путь создания через AccountCreationCoordinator — тот же вызов, что CoreCreate.swift

    @Test("Путь создания — карта: избранное+иконка доходят до стора через координатор")
    func moneyAccountCreationPathPersistsAppearance() throws {
        let ctx = try makeContext()
        let cardData = InlineCardDraft(name: "Дебетовая карта", currency: "RUB", balance: 1_000, isFavorite: true)

        let accountID = try #require(try AccountCreationCoordinator.finalizeMoneyAccount(
            kind: .debitCard,
            selectedProductOption: .card,
            accountName: "Дебетовая карта",
            selectedProductTypeTitle: "Карта",
            cardData: cardData,
            investmentData: nil,
            groupID: nil,
            draftIconName: "star.fill",
            draftIconColor: nil,
            modelContext: ctx
        ))

        let id = try createdAccountID(named: "Дебетовая карта", in: ctx)
        #expect(id == accountID)
        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: id))
        #expect(appearance.isFavorite == true)
        #expect(appearance.iconName == "star.fill")
    }

    @Test("Путь создания — карта без оформления: координатор возвращает id, но строки в AccountAppearance нет")
    func moneyAccountCreationWithoutAppearanceIsNoOp() throws {
        let ctx = try makeContext()
        let cardData = InlineCardDraft(name: "Обычная карта", currency: "RUB", balance: 500)

        let accountID = try #require(try AccountCreationCoordinator.finalizeMoneyAccount(
            kind: .debitCard,
            selectedProductOption: .card,
            accountName: "Обычная карта",
            selectedProductTypeTitle: "Карта",
            cardData: cardData,
            investmentData: nil,
            groupID: nil,
            draftIconName: nil,
            draftIconColor: nil,
            modelContext: ctx
        ))

        #expect(try AccountAppearanceStore(context: ctx).appearance(for: accountID) == nil)
    }

    @Test("Путь создания — кредит: избранное доходит до стора после координатора с loanMeta")
    func loanAccountCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let creditData: AccountCreationCreditDraft = (
            name: "Ипотека", amount: 1_000_000, monthlyPayment: 0, endDate: Date(), remainingAmount: 1_000_000,
            currency: "RUB", bank: .other, creditType: .consumer, isFavorite: true, paymentMode: .dayOfMonth,
            paymentDayOfMonth: 5, nextPaymentDate: nil, reminderEnabled: false, reminderDaysBefore: nil,
            reminderTime: nil, includeInTotal: true
        )

        let accountID = try #require(try AccountCreationCoordinator.finalizeObligationAccount(
            kind: .loan,
            accountName: "Ипотека",
            selectedProductTypeTitle: "Кредит",
            creditData: creditData,
            investmentData: nil,
            loanTermsDraft: nil,
            groupID: nil,
            draftIconName: nil,
            draftIconColor: nil,
            modelContext: ctx
        ))

        let id = try createdAccountID(named: "Ипотека", in: ctx)
        #expect(id == accountID)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }

    /// Баг 1: openingBalance обязан читать `remainingAmount` (текущий остаток долга), а не `amount`
    /// (первоначальную сумму кредита) — иначе уже частично погашенный кредит открылся бы заново
    /// на полную сумму. Если координатор когда-нибудь перепутает поле местами, этот тест ловит
    /// разницу напрямую по сохранённому балансу счёта.
    @Test("Путь создания — кредит: баланс счёта равен remainingAmount, а не amount (Баг 1)")
    func loanAccountCreationUsesRemainingAmountNotPrincipal() throws {
        let ctx = try makeContext()
        let creditData: AccountCreationCreditDraft = (
            name: "Автокредит", amount: 1_000_000, monthlyPayment: 0, endDate: Date(), remainingAmount: 750_000,
            currency: "RUB", bank: .other, creditType: .consumer, isFavorite: false, paymentMode: .dayOfMonth,
            paymentDayOfMonth: 5, nextPaymentDate: nil, reminderEnabled: false, reminderDaysBefore: nil,
            reminderTime: nil, includeInTotal: true
        )

        _ = try #require(try AccountCreationCoordinator.finalizeObligationAccount(
            kind: .loan,
            accountName: "Автокредит",
            selectedProductTypeTitle: "Кредит",
            creditData: creditData,
            investmentData: nil,
            loanTermsDraft: nil,
            groupID: nil,
            draftIconName: nil,
            draftIconColor: nil,
            modelContext: ctx
        ))

        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.name == "Автокредит" })
        let account = try #require(try ctx.fetch(descriptor).first)
        let balance = AccountBalanceEngine.balanceAt(events: account.events ?? [], kind: account.kind, on: Date())
        // Обязательство хранится как отрицательная сумма (движок C) — сравниваем по модулю.
        #expect(abs(balance) == 750_000)
    }

    @Test("Путь создания — долг: избранное доходит до стора через координатор с debtDirection (риск: легко забыть эту ветку)")
    func debtAccountCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let investmentData: AccountCreationInvestmentDraft = (
            name: "Долг Игоря", investmentType: .positive, category: .debt, amount: 30_000, currency: "RUB",
            includeInTotal: true, isFavorite: true, marketData: nil, createCashflowTransaction: false
        )

        let accountID = try #require(try AccountCreationCoordinator.finalizeObligationAccount(
            kind: .debt,
            accountName: "Долг Игоря",
            selectedProductTypeTitle: "Долг",
            creditData: nil,
            investmentData: investmentData,
            loanTermsDraft: nil,
            groupID: nil,
            draftIconName: nil,
            draftIconColor: nil,
            modelContext: ctx
        ))

        let id = try createdAccountID(named: "Долг Игоря", in: ctx)
        #expect(id == accountID)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }

    @Test("Путь создания — ручной актив (недвижимость): избранное доходит до стора (риск: легко забыть house-ветку)")
    func manualAssetHouseCreationPathPersistsFavorite() throws {
        let ctx = try makeContext()
        let investmentData: AccountCreationInvestmentDraft = (
            name: "Квартира", investmentType: .positive, category: .house, amount: 5_000_000, currency: "RUB",
            includeInTotal: true, isFavorite: true, marketData: nil, createCashflowTransaction: false
        )

        let accountID = try #require(try AccountCreationCoordinator.finalizeAssetAccount(
            kind: .manualAsset,
            selectedProductOption: .house,
            accountName: "Квартира",
            selectedProductTypeTitle: "Недвижимость",
            investmentData: investmentData,
            groupID: nil,
            realEstatePropertyType: .apartment,
            realEstatePhotoData: [],
            draftIconName: nil,
            draftIconColor: nil,
            modelContext: ctx
        ))

        let id = try createdAccountID(named: "Квартира", in: ctx)
        #expect(id == accountID)
        #expect(try AccountAppearanceStore(context: ctx).isFavorite(accountID: id) == true)
    }

    @Test("Путь создания — вклад: иконка/цвет доходят до стора, isFavorite всегда false (у вклада нет тумблера)")
    func depositCreationPathPersistsIconIgnoresFavoriteToggle() throws {
        let ctx = try makeContext()
        let depositData = DepositFormData(
            amount: 100_000, currency: "RUB", rate: 12, capitalization: .monthly, termEnd: nil,
            payoutDay: 1, allowsTopUp: true, allowsEarlyClose: true, earlyClosePenaltyPercent: 0,
            remindEnd: false, autoRollover: false, comment: "", isTaxable: false
        )

        let accountID = try #require(try AccountCreationCoordinator.finalizeDepositAccount(
            accountName: "Вклад",
            selectedProductTypeTitle: "Вклад",
            depositData: depositData,
            groupID: nil,
            draftIconName: "banknote",
            draftIconColor: "#00FF00",
            modelContext: ctx
        ))

        let id = try createdAccountID(named: "Вклад", in: ctx)
        #expect(id == accountID)
        let appearance = try #require(try AccountAppearanceStore(context: ctx).appearance(for: id))
        #expect(appearance.isFavorite == false)
        #expect(appearance.iconName == "banknote")
        #expect(appearance.tintHex == "#00FF00")
    }
}
