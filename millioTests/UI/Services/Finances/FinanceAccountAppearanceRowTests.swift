import Foundation
import SwiftData
import Testing
@testable import millio

/// Ф1 редизайна карточек счетов: строка списка берёт монограмму/цвет/«избранное» из
/// `AccountAppearance` (V11) через ОДИН fetch во ViewModel, а не запросом на строку.
@Suite(.serialized)
@MainActor
struct FinanceAccountAppearanceRowTests {

    // `loadAccounts` планирует fire-and-forget Task, трогающий стор после возврата из теста.
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

    @discardableResult
    private func makeAccount(_ ctx: ModelContext, name: String, balance: Decimal = 0) throws -> Account {
        let account = try AccountsCoreService(modelContext: ctx).createAccount(
            name: name, kind: .debitCard, currency: "RUB", openingBalance: balance, group: nil
        )
        try ctx.save()
        return account
    }

    // MARK: - Резолв визуала строки

    @Test("Без оформления строка рисует монограмму по имени — вид как до V11")
    func missingAppearanceKeepsMonogramDefault() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: "Сбербанк")

        let details = CashflowAccountPickerDetailsFactory.details(
            for: account, appearance: nil, balance: 0
        )

        #expect(details.iconName == AccountIconSet.monogramIconName("Сбербанк"))
        #expect(details.iconColorHex == nil)
        #expect(details.fallbackIconName == AccountKind.debitCard.fallbackIconName)
    }

    @Test("Оформление перебивает монограмму: иконка и цвет берутся из AccountAppearance")
    func appearanceOverridesIconAndTint() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: "Сбербанк")
        let appearance = AccountAppearanceSnapshot(iconName: "bitcoinsign.circle.fill", tintHex: "#10B981")

        let details = CashflowAccountPickerDetailsFactory.details(
            for: account, appearance: appearance, balance: 0
        )

        #expect(details.iconName == "bitcoinsign.circle.fill")
        #expect(details.iconColorHex == "#10B981")
    }

    /// Оформление есть, но иконка в нём не задана (выбран только цвет) — монограмма обязана
    /// вернуться, иначе бейдж молча свалится на общий SF Symbol типа счёта.
    @Test("Оформление без иконки не ломает монограмму")
    func appearanceWithoutIconFallsBackToMonogram() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: "Тинькофф")

        let details = CashflowAccountPickerDetailsFactory.details(
            for: account,
            appearance: AccountAppearanceSnapshot(iconName: nil, tintHex: "#FF0000"),
            balance: 0
        )

        #expect(details.iconName == AccountIconSet.monogramIconName("Тинькофф"))
        #expect(details.iconColorHex == "#FF0000")
    }

    /// Одноимённые счета дают одинаковую монограмму — это ожидаемое поведение, не баг:
    /// различать их пользователь может цветом/иконкой из галереи (Ф2).
    @Test("Одноимённые счета получают одинаковую монограмму — зафиксированное ожидание")
    func sameNameAccountsShareMonogram() throws {
        let ctx = try makeContext()
        let first = try makeAccount(ctx, name: "Копилка")
        let second = try makeAccount(ctx, name: "Копилка")

        let a = CashflowAccountPickerDetailsFactory.details(for: first, balance: 0)
        let b = CashflowAccountPickerDetailsFactory.details(for: second, balance: 0)

        #expect(a.iconName == b.iconName)
    }

    @Test("Очень длинное имя усекается до монограммы, а не течёт в бейдж целиком")
    func longNameIsTrimmedToMonogram() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: String(repeating: "Длинное имя ", count: 20))

        let details = CashflowAccountPickerDetailsFactory.details(for: account, balance: 0)
        let text = AccountIconSet.monogramText(details.iconName ?? "")

        #expect(text.count <= 3)
    }

    // MARK: - Один fetch на список, а не N

    /// Строка обязана читать КЭШ ViewModel. Доказательство: после `loadAccountAppearances()`
    /// сносим строки оформления из стора — значение всё равно отдаётся, значит запроса на строку нет.
    @Test("appearance(for:) читает кэш ViewModel, а не стор на каждый вызов")
    func appearanceIsServedFromCacheNotPerRowFetch() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: "Кэш")
        let store = AccountAppearanceStore(context: ctx)
        try store.upsert(accountID: account.id) { $0.tintHex = "#123456" }
        try ctx.save()

        let vm = makeViewModel(ctx)
        vm.loadAccountAppearances()
        #expect(vm.appearance(for: account)?.tintHex == "#123456")

        for row in try ctx.fetch(FetchDescriptor<AccountAppearance>()) { ctx.delete(row) }
        try ctx.save()

        #expect(vm.appearance(for: account)?.tintHex == "#123456")
    }

    @Test("Пустой стор оформлений даёт пустой словарь, а не падение")
    func emptyAppearanceStoreYieldsEmptyDictionary() throws {
        let ctx = try makeContext()
        let account = try makeAccount(ctx, name: "Без оформления")

        let vm = makeViewModel(ctx)
        vm.loadAccountAppearances()

        #expect(vm.accountAppearances.isEmpty)
        #expect(vm.appearance(for: account) == nil)
    }

    // MARK: - Избранное

    @Test("Избранный счёт поднимается в начало списка независимо от режима сортировки")
    func favoriteAccountSortsFirst() throws {
        let ctx = try makeContext()
        try makeAccount(ctx, name: "Аврора", balance: 10_000)
        let last = try makeAccount(ctx, name: "Ясень", balance: 1)

        let vm = makeViewModel(ctx)
        vm.handle(.setAccountSortMode(.nameAscending))
        #expect(vm.ungroupedAccounts().map(\.name) == ["Аврора", "Ясень"])

        vm.toggleFavorite(last)

        #expect(vm.ungroupedAccounts().map(\.name) == ["Ясень", "Аврора"])
    }

    @Test("Снятие звезды возвращает прежний порядок")
    func unfavoriteRestoresOrder() throws {
        let ctx = try makeContext()
        try makeAccount(ctx, name: "Аврора", balance: 10_000)
        let last = try makeAccount(ctx, name: "Ясень", balance: 1)

        let vm = makeViewModel(ctx)
        vm.handle(.setAccountSortMode(.nameAscending))
        vm.toggleFavorite(last)
        vm.toggleFavorite(last)

        #expect(vm.ungroupedAccounts().map(\.name) == ["Аврора", "Ясень"])
        #expect(vm.appearance(for: last)?.isFavorite != true)
    }

    /// Порядок строк и звезда на строке обязаны опираться на ОДИН срез: если бы сортировка ходила
    /// в стор, а строка — в кэш, счёт стоял бы наверху без звезды (класс «двойник источника»).
    @Test("Звезда на строке и позиция в списке приходят из одного среза")
    func favoriteBadgeAndOrderShareSingleSlice() throws {
        let ctx = try makeContext()
        try makeAccount(ctx, name: "Аврора")
        let starred = try makeAccount(ctx, name: "Ясень")

        let vm = makeViewModel(ctx)
        vm.toggleFavorite(starred)

        let ordered = vm.ungroupedAccounts()
        #expect(ordered.first?.id == starred.id)
        #expect(vm.appearance(for: ordered[0])?.isFavorite == true)
    }
}
