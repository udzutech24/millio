import Foundation
import SwiftData
import Testing
@testable import millio

/// Единая строка счёта: детерминированный дефолт оформления + приоритет источников.
/// Проверяем ЛОГИКУ презентации (не рендеринг): именно она отвечает за то, что новый вид
/// появляется на всех счетах сразу после установки, без ручной настройки.
@Suite(.serialized)
@MainActor
struct AccountRowPresentationTests {

    // MARK: - Детерминированный дефолт

    @Test("Цвет по умолчанию стабилен: один ключ — один цвет, между вызовами не меняется")
    func defaultTintIsDeterministic() {
        let key = UUID().uuidString
        let first = AccountAppearanceDefaults.tintHex(forKey: key)
        #expect(first != nil)
        #expect(first == AccountAppearanceDefaults.tintHex(forKey: key))
        // Значение обязано быть из палитры, а не произвольным hex.
        #expect(AccountAppearanceDefaults.autoPalette.contains(first ?? ""))
    }

    @Test("Разные счета получают разные цвета — палитра действительно распределяется")
    func defaultTintSpreadsAcrossPalette() {
        let colors = Set((0..<200).map { AccountAppearanceDefaults.tintHex(forKey: "account-\($0)") })
        #expect(colors.count == AccountAppearanceDefaults.autoPalette.count)
    }

    @Test("Красный и серый в авто-подбор не попадают: красный зарезервирован за долгом")
    func autoPaletteExcludesReservedColors() {
        #expect(!AccountAppearanceDefaults.autoPalette.contains("#EF4444"))
        #expect(!AccountAppearanceDefaults.autoPalette.contains("#6B7280"))
        #expect(AccountAppearanceDefaults.autoPalette.count == AccountIconSet.palette.count - 2)
    }

    @Test("Пустой ключ цвета не даёт — счёт остаётся на градиенте, а не падает")
    func emptyKeyHasNoDefaultTint() {
        #expect(AccountAppearanceDefaults.tintHex(forKey: "") == nil)
    }

    // MARK: - Приоритет источников

    @Test("Приоритет: выбор пользователя → легаси-поля счёта → детерминированный дефолт")
    func resolverPriority() {
        let key = "KEY-1"
        let chosen = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Сбербанк",
            appearance: AccountAppearanceSnapshot(iconName: "star.fill", tintHex: "#111111"),
            legacyIconName: "creditcard.fill",
            legacyIconColorHex: "#222222"
        )
        #expect(chosen.iconName == "star.fill")
        #expect(chosen.iconColorHex == "#111111")

        let legacy = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Сбербанк",
            appearance: nil,
            legacyIconName: "creditcard.fill",
            legacyIconColorHex: "#222222"
        )
        #expect(legacy.iconName == "creditcard.fill")
        #expect(legacy.iconColorHex == "#222222")

        let fallback = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: key,
            name: "Сбербанк",
            appearance: nil
        )
        #expect(fallback.iconName == AccountIconSet.monogramIconName("Сбербанк"))
        #expect(fallback.iconColorHex == AccountAppearanceDefaults.tintHex(forKey: key))
    }

    @Test("Пустое имя не даёт пустой бейдж: иконка nil → строка берёт fallback типа продукта")
    func emptyNameFallsBackToTypeIcon() {
        let resolved = CashflowAccountPickerDetailsFactory.resolvedAppearance(
            key: "KEY-2",
            name: "   ",
            appearance: nil
        )
        #expect(resolved.iconName == nil)
    }

    @Test("Переименование счёта цвет не меняет — ключ берётся из идентификатора, не из имени")
    func renameKeepsTint() {
        let key = UUID().uuidString
        let before = CashflowAccountPickerDetailsFactory.resolvedAppearance(key: key, name: "Старое", appearance: nil)
        let after = CashflowAccountPickerDetailsFactory.resolvedAppearance(key: key, name: "Новое имя", appearance: nil)
        #expect(before.iconColorHex == after.iconColorHex)
        #expect(before.iconName != after.iconName)
    }

    // MARK: - Презентация строки

    @Test("Core-счёт без оформления получает новый вид: монограмма + цвет из палитры")
    func coreAccountGetsNewLookWithoutAppearance() {
        let account = Account(name: "Наличные", kind: .cash, currency: "RUB")
        let presentation = AccountRowPresentation.make(
            key: account.id.uuidString,
            name: account.name,
            appearance: nil,
            fallbackIconName: account.kind.fallbackIconName,
            amountText: "1 000",
            currencySymbol: "₽"
        )
        #expect(presentation.iconName == AccountIconSet.monogramIconName("Наличные"))
        #expect(presentation.iconColorHex != nil)
        #expect(presentation.isFavorite == false)
    }

    @Test("Легаси-карта без персонализации тоже получает новый вид (это и был баг)")
    func legacyCardGetsNewLook() {
        let card = Card(name: "Тинькофф", cardNumber: "1234")
        let details = CashflowAccountPickerDetailsFactory.details(for: card)
        #expect(details.iconColorHex == AccountAppearanceDefaults.tintHex(forKey: card.cardUniqueID))
        #expect(details.iconName == AccountIconSet.monogramIconName("Тинькофф"))
    }

    @Test("Избранное прокидывается из оформления в презентацию строки")
    func favoriteReachesPresentation() {
        let presentation = AccountRowPresentation.make(
            key: "KEY-3",
            name: "Вклад",
            appearance: AccountAppearanceSnapshot(isFavorite: true),
            fallbackIconName: "lock.fill",
            amountText: "10",
            currencySymbol: "₽"
        )
        #expect(presentation.isFavorite)
    }

    @Test("Скрытие сумм заменяет цифры точками, не подставляя ноль")
    func hiddenAmountIsMasked() {
        #expect(AccountRowAmountFormatter.text(12_345, isHidden: true) == "•••••")
        #expect(AccountRowAmountFormatter.text(0, isHidden: true) == "•••")
        #expect(AccountRowAmountFormatter.text(1234.56, isHidden: false, maximumFractionDigits: 2).hasSuffix("34,56")
                || AccountRowAmountFormatter.text(1234.56, isHidden: false, maximumFractionDigits: 2).hasSuffix("34.56"))
    }

    // MARK: - Путь создания (не только трансформация)

    /// `millio-integration-test-creation-path`: пишем оформление ТЕМ ЖЕ путём, которым это делает
    /// строка списка (ViewModel → стор), и читаем его обратно тем же, которым читает строка.
    @Test("Путь создания: выбор оформления легаси-счёта сохраняется и доезжает до строки")
    func legacyAppearanceRoundTripThroughViewModel() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let card = Card(name: "Альфа", cardNumber: "9999")
        context.insert(card)
        let financeAccount = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        context.insert(financeAccount)
        try context.save()

        let viewModel = FinanceViewModel(
            modelContext: context,
            currencyService: MockCurrencyRateService(),
            skipInitialLoad: true
        )
        #expect(viewModel.appearance(for: financeAccount) == nil)

        viewModel.saveAppearance(iconName: "bolt.fill", tintHex: "#ABCDEF", for: financeAccount)

        let stored = try #require(viewModel.appearance(for: financeAccount))
        #expect(stored.iconName == "bolt.fill")
        #expect(stored.tintHex == "#ABCDEF")

        // Строка рисует выбранное, а не дефолт.
        let presentation = AccountRowPresentation.make(
            key: financeAccount.accountID,
            name: card.name,
            appearance: viewModel.appearance(for: financeAccount),
            fallbackIconName: card.cardType.icon,
            amountText: "0",
            currencySymbol: "₽"
        )
        #expect(presentation.iconColorHex == "#ABCDEF")

        // И переживает чистку сирот на следующем старте.
        try DataIntegrityCleaner.purgeOrphanAccountAppearancesOnLaunch(modelContext: context)
        let afterLaunch = try AccountAppearanceStore(context: context).loadSnapshots()
        let cardUUID = try #require(UUID(uuidString: card.cardUniqueID))
        #expect(afterLaunch[cardUUID]?.tintHex == "#ABCDEF")
    }

    @Test("Полный сброс оформления удаляет строку — счёт возвращается к вычисляемому дефолту")
    func resettingAppearanceRemovesRow() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Копилка", kind: .cash, currency: "RUB")
        context.insert(account)
        try context.save()

        let store = AccountAppearanceStore(context: context)
        try store.setAppearance(accountID: account.id, iconName: "star.fill", tintHex: "#FFFFFF")
        try context.save()
        #expect(try store.loadAll()[account.id] != nil)

        try store.setAppearance(accountID: account.id, iconName: nil, tintHex: nil)
        try context.save()
        #expect(try store.loadAll()[account.id] == nil)
    }

    @Test("Сброс не трогает избранное: строка остаётся, если счёт в избранном")
    func resettingAppearanceKeepsFavorite() throws {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let context = container.mainContext
        let account = Account(name: "Копилка", kind: .cash, currency: "RUB")
        context.insert(account)
        try context.save()

        let store = AccountAppearanceStore(context: context)
        try store.upsert(accountID: account.id) { $0.isFavorite = true }
        try store.setAppearance(accountID: account.id, iconName: nil, tintHex: nil)
        try context.save()

        #expect(try store.loadAll()[account.id]?.isFavorite == true)
    }
}
