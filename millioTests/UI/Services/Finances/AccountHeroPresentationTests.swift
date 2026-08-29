import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф3: hero-карточка детального экрана счёта.
///
/// Главный инвариант — сумма hero совпадает со строкой списка и с вкладом счёта в тотал.
/// Расхождение здесь и есть тот класс багов, которым проект болел («деталка показывает одно,
/// список другое»), поэтому проверяем ЧИСЛО, а не вёрстку.
@Suite(.serialized)
@MainActor
struct AccountHeroPresentationTests {

    private static var retained: [AnyObject] = []

    private func makeContext() throws -> ModelContext {
        UserDefaults.standard.set("RUB", forKey: "primaryCurrencyCode")
        let container = try AppMigrationPlan.makeInMemoryContainer()
        Self.retained.append(container)
        return container.mainContext
    }

    private func makeViewModel(_ ctx: ModelContext) -> FinanceViewModel {
        let service = MockCurrencyRateService()
        service.usdBasedRates = ["RUB": 90]
        let vm = FinanceViewModel(modelContext: ctx, currencyService: service, skipInitialLoad: true)
        vm.state.displayCurrency = "RUB"
        Self.retained.append(vm)
        Self.retained.append(service)
        return vm
    }

    /// Та же формула суммы, что у hero в `AccountDetailView.heroAmount`: подтверждённый баланс,
    /// приведённый к знаку вклада в тотал.
    private func heroAmount(for account: Account) -> Decimal {
        let raw = AccountBalanceEngine.balanceAt(
            events: DepositConfirmedBalanceResolver.confirmedEvents(
                account.events ?? [], accountID: account.id, kind: account.kind
            ),
            kind: account.kind,
            on: Date(),
            marketMeta: account.marketMeta
        )
        return AccountTotalsContribution.signedValue(
            rawBalance: raw,
            kind: account.kind,
            creditLimit: account.cardMeta?.creditLimit
        )
    }

    // MARK: - Инвариант «hero == строка списка»

    @Test("Обычный счёт: сумма hero совпадает со строкой списка до копейки")
    func heroBalanceMatchesRow() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        let account = try AccountsCoreService(modelContext: ctx).createAccount(
            name: "Наличные", kind: .cash, currency: "RUB", openingBalance: 12_345, group: nil
        )
        try ctx.save()

        #expect(heroAmount(for: account) == vm.newCoreBalanceToday(account))
    }

    @Test("Вклад: hero берёт ПОДТВЕРЖДЁННЫЙ баланс, а не сырой реплей прогнозов")
    func depositHeroUsesConfirmedBalance() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        let account = try AccountsCoreService(modelContext: ctx).createAccount(
            name: "Вклад", kind: .deposit, currency: "RUB", openingBalance: 100_000, group: nil
        )
        // Будущее начисление: в сырой реплей оно попадает, в подтверждённый баланс — нет.
        let future = AccountEvent(
            account: account,
            date: Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date(),
            type: .interest,
            amount: 5_000
        )
        ctx.insert(future)
        account.events = (account.events ?? []) + [future]
        try ctx.save()

        let rawReplay = AccountBalanceEngine.balanceAt(
            events: account.events ?? [],
            kind: .deposit,
            on: Calendar.current.date(byAdding: .month, value: 2, to: Date()) ?? Date()
        )
        #expect(heroAmount(for: account) == vm.newCoreBalanceToday(account))
        #expect(heroAmount(for: account) != rawReplay)
    }

    @Test("Нулевой баланс не ломает hero и совпадает со строкой")
    func zeroBalanceIsConsistent() throws {
        let ctx = try makeContext()
        let vm = makeViewModel(ctx)
        let account = try AccountsCoreService(modelContext: ctx).createAccount(
            name: "Пустой", kind: .cash, currency: "RUB", openingBalance: 0, group: nil
        )
        try ctx.save()

        #expect(heroAmount(for: account) == 0)
        #expect(heroAmount(for: account) == vm.newCoreBalanceToday(account))
    }

    // MARK: - Презентация

    @Test("Оформление hero резолвится тем же резолвером, что строка списка")
    func heroUsesSharedResolver() {
        let key = UUID().uuidString
        let appearance = AccountAppearanceSnapshot(iconName: "star.fill", tintHex: "#112233")
        let hero = AccountHeroPresentation.make(
            key: key,
            name: "Счёт",
            appearance: appearance,
            fallbackIconName: "banknote.fill",
            amountText: "1 000",
            currencySymbol: "₽"
        )
        let row = AccountRowPresentation.make(
            key: key,
            name: "Счёт",
            appearance: appearance,
            fallbackIconName: "banknote.fill",
            amountText: "1 000",
            currencySymbol: "₽"
        )
        #expect(hero.iconName == row.iconName)
        #expect(hero.iconColorHex == row.iconColorHex)
    }

    @Test("Дизайн из Ф2 даёт hero градиент, без дизайна — подложка из акцента счёта")
    func heroGradientFollowsPreset() {
        let withPreset = AccountHeroPresentation.make(
            key: UUID().uuidString,
            name: "Счёт",
            appearance: AccountAppearanceSnapshot(presetRaw: AccountAppearancePreset.ocean.rawValue),
            fallbackIconName: "banknote.fill",
            amountText: "0",
            currencySymbol: "₽"
        )
        #expect(withPreset.gradientHexes == AccountAppearancePreset.ocean.gradientHexes)
        #expect(withPreset.gradientColors.count == 2)

        let withoutPreset = AccountHeroPresentation.make(
            key: UUID().uuidString,
            name: "Счёт",
            appearance: nil,
            fallbackIconName: "banknote.fill",
            amountText: "0",
            currencySymbol: "₽"
        )
        #expect(withoutPreset.gradientHexes.isEmpty)
        // Подложка всё равно есть: без неё карточка была бы прозрачной.
        #expect(withoutPreset.gradientColors.count == 2)
    }

    @Test("Неизвестный дизайн из чужого бэкапа не роняет hero — карточка остаётся с подложкой")
    func unknownPresetKeepsHeroRenderable() {
        let hero = AccountHeroPresentation.make(
            key: UUID().uuidString,
            name: "Счёт",
            appearance: AccountAppearanceSnapshot(presetRaw: "дизайн-из-будущего"),
            fallbackIconName: "banknote.fill",
            amountText: "0",
            currencySymbol: "₽"
        )
        #expect(hero.gradientHexes.isEmpty)
        #expect(!hero.gradientColors.isEmpty)
    }

    @Test("Архив и «не в тотале» — разные бейджи, показываются одновременно")
    func statusBadgesAreDistinct() {
        let hero = AccountHeroPresentation(
            name: "Счёт",
            subtitle: nil,
            typeTitle: nil,
            amountText: "0",
            currencySymbol: "₽",
            isNegative: false,
            iconName: nil,
            iconColorHex: nil,
            fallbackIconName: "banknote.fill",
            gradientHexes: [],
            detailLines: [],
            badges: [
                .init(text: "Архив", systemImage: "archivebox"),
                .init(text: "Не в тотале", systemImage: "sum"),
            ]
        )
        #expect(hero.badges.count == 2)
        #expect(Set(hero.badges.map(\.id)).count == 2)
    }

    @Test("Очень длинное имя и большая сумма сохраняются целиком — обрезает вёрстка, не модель")
    func longNameAndAmountArePreserved() {
        let name = String(repeating: "Очень длинное имя счёта ", count: 6)
        let hero = AccountHeroPresentation.make(
            key: UUID().uuidString,
            name: name,
            appearance: nil,
            fallbackIconName: "banknote.fill",
            amountText: AccountRowAmountFormatter.text(987_654_321_012, isHidden: false),
            currencySymbol: "₽"
        )
        #expect(hero.name == name)
        #expect(hero.amountText.contains("987"))
    }

    @Test("Названия типов продуктов локализованы — hero-капсула не показывает сырой ключ")
    func kindTitlesAreLocalized() {
        for kind in AccountKind.allCases {
            let title = kind.localizedTitle
            #expect(!title.isEmpty)
            #expect(!title.hasPrefix("accounts_core.kind."))
        }
    }
}
