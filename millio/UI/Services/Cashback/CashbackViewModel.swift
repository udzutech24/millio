//
//  CashbackViewModel.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation
import SwiftData
import SwiftUI
import Combine

// MARK: - Cashback State

struct CashbackState {
    /// Все кешбэки
    var cashbacks: [Cashback] = []

    /// Кешбэки выбранного месяца
    var visibleCashbacks: [Cashback] = []
    
    /// Показывать ли экран добавления/редактирования
    var showCashbackEditor: Bool = false
    
    /// Редактируемый кешбэк (nil = новый)
    var editingCashback: Cashback? = nil
    
    /// Показывать ли экран выбора карты
    var showCardPicker: Bool = false
    
    /// Все доступные карты
    var availableAccounts: [CashflowSelectableAccount] = []

    /// Пользовательские категории кешбэка
    var customCategories: [CashbackCustomCategory] = []

    /// Выбранный месяц на экране кешбэка
    var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    /// Избранные категории кешбэка (raw keys)
    var favoriteCategoryRaws: Set<String> = []

    /// Закрепленные позиции кешбэка (уникальные ключи строк)
    var pinnedCashbackKeys: Set<String> = []

    /// Скрытые категории кешбэка (raw keys)
    var hiddenCategoryRaws: Set<String> = []
}

// MARK: - Cashback Actions

enum CashbackAction {
    case loadCashbacks
    case loadCards
    case loadCustomCategories
    case createCustomCategory(String)
    case setSelectedMonth(Date)
    case moveMonthBackward
    case moveMonthForward
    case renameCustomCategory(rawValue: String, newName: String)
    case deleteCustomCategory(rawValue: String)
    case toggleFavoriteCategory(rawValue: String)
    case togglePinnedCashback(Cashback)
    case addCashback
    case editCashback(Cashback)
    case deleteCashback(Cashback)
    case updateCashback(category: CashbackCategory, percentage: Double, cardIDs: [String])
    case updateCashbacksForCard(
        cardID: String,
        cashbacks: [(categoryRaw: String, categoryName: String, percentage: Double)]
    )
    case showCashbackEditor
    case hideCashbackEditor
    case showCardPicker
    case hideCardPicker
}

// MARK: - Cashback ViewModel

@MainActor
final class CashbackViewModel: ViewModelProtocol {
    @Published var state = CashbackState()
    
    let modelContext: ModelContext
    private let now: () -> Date
    private let importedCategoryResolver: CashbackImportCategoryResolver
    private let defaults: UserDefaults
    private static let favoriteCategoryRawsKey = "cashback.favorite_category_raws"
    private static let pinnedCashbackKeysKey = "cashback.pinned_cashback_keys"
    private static let legacyPinnedCategoryRawsKey = "cashback.pinned_category_raws"
    private static let hiddenCategoryRawsKey = "cashback.hidden_category_raws"
    
    init(
        modelContext: ModelContext,
        now: @escaping () -> Date = Date.init,
        importedCategoryResolver: CashbackImportCategoryResolver = CashbackImportCategoryResolver(),
        defaults: UserDefaults = .standard
    ) {
        self.modelContext = modelContext
        self.now = now
        self.importedCategoryResolver = importedCategoryResolver
        self.defaults = defaults
        self.state.selectedMonth = Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now())
        ) ?? now()
        self.state.favoriteCategoryRaws = loadFavoriteCategoryRaws()
        self.state.pinnedCashbackKeys = loadPinnedCashbackKeys()
        self.state.hiddenCategoryRaws = loadHiddenCategoryRaws()
        // Инициализируем CardManager
        CardManager.shared.setup(modelContext: modelContext)
        // Сначала загружаем карты, потом кешбэки, чтобы правильно проверить связи
        loadCards()
        loadCustomCategories()
        loadCashbacks()
        
        #if DEBUG
        AppLogger.log(.debug, category: "Cashback", "Loaded \(state.availableAccounts.count) accounts, \(state.cashbacks.count) cashbacks")
        #endif
        
        // Автоматически проверяем и очищаем невалидные связи при первом запуске
        cleanInvalidCardIDs(in: state.cashbacks)
        
        // НЕ вызываем cleanInvalidCardIDs здесь - это может удалить валидные связи
        // Очистка будет происходить только при реальном удалении карт в loadCards()
    }
    
    func handle(_ action: CashbackAction) {
        switch action {
        case .loadCashbacks:
            loadCashbacks()
            
        case .loadCards:
            loadCards()

        case .loadCustomCategories:
            loadCustomCategories()

        case .createCustomCategory(let name):
            createCustomCategory(name)

        case .setSelectedMonth(let date):
            let normalized = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: date)
            ) ?? date
            let current = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month], from: now())
            ) ?? now()
            state.selectedMonth = min(normalized, current)
            applyFilters()

        case .moveMonthBackward:
            shiftSelectedMonth(by: -1)

        case .moveMonthForward:
            shiftSelectedMonth(by: 1)

        case .renameCustomCategory(let rawValue, let newName):
            _ = renameCustomCategory(rawValue: rawValue, newName: newName)

        case .deleteCustomCategory(let rawValue):
            _ = deleteCustomCategory(rawValue: rawValue)

        case .toggleFavoriteCategory(let rawValue):
            toggleFavoriteCategory(rawValue: rawValue)

        case .togglePinnedCashback(let cashback):
            togglePinnedCashback(cashback)
            
        case .addCashback:
            state.editingCashback = nil
            state.showCashbackEditor = true
            
        case .editCashback(let cashback):
            state.editingCashback = cashback
            state.showCashbackEditor = true
            
        case .deleteCashback(let cashback):
            deleteCashback(cashback)
            
        case .updateCashback(let category, let percentage, let cardIDs):
            updateCashback(category: category, percentage: percentage, cardIDs: cardIDs)
            
        case .updateCashbacksForCard(let cardID, let cashbacks):
            updateCashbacksForCard(cardID: cardID, cashbacks: cashbacks)
            
        case .showCashbackEditor:
            state.showCashbackEditor = true
            
        case .hideCashbackEditor:
            state.showCashbackEditor = false
            state.editingCashback = nil
            
        case .showCardPicker:
            loadCards() // Обновляем список перед показом
            state.showCardPicker = true
            
        case .hideCardPicker:
            state.showCardPicker = false
            
        }
    }

    // MARK: - Categories

    func categoryOptions(matching query: String = "", includeHidden: Bool = false) -> [CashbackCategoryOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allOptions = (systemCategoryOptions + customCategoryOptions)
            .filter { includeHidden || !state.hiddenCategoryRaws.contains($0.rawValue) }

        guard !trimmedQuery.isEmpty else { return allOptions }

        return allOptions.filter { option in
            if option.isCustom {
                return option.displayName.localizedCaseInsensitiveContains(trimmedQuery)
            }
            return CashbackCategoryCatalog.matchesSearch(rawValue: option.rawValue, query: trimmedQuery)
        }
    }

    /// Категории для экрана избранного без дублей по смыслу.
    /// Импортные кастомные ярлыки схлопываются в системную категорию, если резолвер знает эквивалент.
    func favoriteCategoryOptions(matching query: String = "") -> [CashbackCategoryOption] {
        let options = categoryOptions(matching: query, includeHidden: true)
        var uniqueByCanonicalRaw: [String: CashbackCategoryOption] = [:]

        for option in options {
            let presented = presentedFavoriteCategoryOption(for: option)
            if let existing = uniqueByCanonicalRaw[presented.rawValue] {
                uniqueByCanonicalRaw[presented.rawValue] = preferredFavoriteCategoryOption(lhs: existing, rhs: presented)
            } else {
                uniqueByCanonicalRaw[presented.rawValue] = presented
            }
        }

        return Array(uniqueByCanonicalRaw.values)
    }

    func categoryOption(for raw: String, fallbackName: String = "") -> CashbackCategoryOption {
        if let system = CashbackCategory(rawValue: raw) {
            return CashbackCategoryOption(
                rawValue: raw,
                displayName: system.displayName,
                icon: system.icon,
                isCustom: false
            )
        }

        if let customCategoryID = Self.customCategoryID(from: raw),
           let custom = state.customCategories.first(where: { $0.categoryID == customCategoryID }) {
            return CashbackCategoryOption(
                rawValue: raw,
                displayName: custom.name,
                icon: resolvedIcon(for: custom.name, storedIcon: custom.icon),
                isCustom: true
            )
        }

        let safeFallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CashbackCategoryOption(
            rawValue: raw,
            displayName: safeFallbackName.isEmpty ? CashbackCategory.other.displayName : safeFallbackName,
            icon: resolvedIcon(
                for: safeFallbackName.isEmpty ? CashbackCategory.other.displayName : safeFallbackName,
                storedIcon: CashbackCustomCategory.defaultIcon
            ),
            isCustom: true
        )
    }

    func categoryOptionForImportedName(_ name: String) -> CashbackCategoryOption {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return categoryOption(for: CashbackCategory.other.rawValue)
        }

        if let systemRaw = importedCategoryResolver.resolveSystemCategoryRawForImport(trimmed) {
            return categoryOption(for: systemRaw, fallbackName: trimmed)
        }

        if let custom = createCustomCategory(trimmed) {
            return custom
        }

        return categoryOption(for: CashbackCategory.other.rawValue, fallbackName: trimmed)
    }

    func isFavoriteCategory(rawValue: String) -> Bool {
        state.favoriteCategoryRaws.contains(canonicalFavoriteRaw(for: rawValue))
    }

    func isFavoriteCategory(rawValue: String, fallbackName: String) -> Bool {
        state.favoriteCategoryRaws.contains(canonicalFavoriteRaw(for: rawValue, fallbackName: fallbackName))
    }

    func isPinnedCashback(_ cashback: Cashback) -> Bool {
        state.pinnedCashbackKeys.contains(pinnedCashbackKey(for: cashback))
    }

    var selectedMonthTitle: String {
        selectedMonthTitle(locale: CashbackL10n.locale)
    }

    func selectedMonthTitle(locale: Locale) -> String {
        let month = CashbackMonthTitleFormatter.monthText(for: state.selectedMonth, locale: locale)
        let year = CashbackMonthTitleFormatter.yearText(for: state.selectedMonth, locale: locale)
        return "\(month.capitalized) \(year)"
    }

    var maxSelectableMonth: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now())
        ) ?? now()
    }

    var minSelectableMonth: Date {
        let months = state.cashbacks.compactMap { Cashback.startOfMonth(for: $0.monthKey) }
        if let earliestCashbackMonth = months.min() {
            return earliestCashbackMonth
        }

        let fallback = Calendar.current.date(byAdding: .month, value: -24, to: maxSelectableMonth)
        return fallback ?? maxSelectableMonth
    }

    func canMoveMonthForward() -> Bool {
        let calendar = Calendar.current
        let selected = calendar.date(
            from: calendar.dateComponents([.year, .month], from: state.selectedMonth)
        ) ?? state.selectedMonth
        let current = maxSelectableMonth
        return selected < current
    }

    func canMoveMonthBackward() -> Bool {
        let calendar = Calendar.current
        let selected = calendar.date(
            from: calendar.dateComponents([.year, .month], from: state.selectedMonth)
        ) ?? state.selectedMonth
        let minMonth = minSelectableMonth
        return selected > minMonth
    }

    @discardableResult
    func createCustomCategory(_ name: String, icon: String = CashbackCustomCategory.defaultIcon) -> CashbackCategoryOption? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalizedIcon = CashbackCustomCategory.normalizeIcon(icon)

        if let systemMatch = systemCategoryOptions.first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            // Если пользователь оставил системное имя, но явно выбрал другую иконку,
            // это уже отдельная кастомная категория, а не alias системной.
            if normalizedIcon == systemMatch.icon {
                return systemMatch
            }
        }

        let normalized = CashbackCustomCategory.normalize(trimmed)
        if let existing = state.customCategories.first(where: { $0.normalizedName == normalized }) {
            return categoryOption(for: Self.customRawValue(from: existing.categoryID), fallbackName: existing.name)
        }

        let customCategory = CashbackCustomCategory(name: trimmed, icon: normalizedIcon)
        modelContext.insert(customCategory)

        do {
            try modelContext.save()
            loadCustomCategories()
            return categoryOption(for: Self.customRawValue(from: customCategory.categoryID), fallbackName: customCategory.name)
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to create custom category: \(error.localizedDescription)")
            return nil
        }
    }

    @discardableResult
    func renameCustomCategory(
        rawValue: String,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        guard let sourceCustomID = Self.customCategoryID(from: rawValue),
              let sourceCategory = state.customCategories.first(where: { $0.categoryID == sourceCustomID }) else {
            return false
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = CashbackCustomCategory.normalize(trimmed)
        let normalizedIcon = CashbackCustomCategory.normalizeIcon(newIcon ?? sourceCategory.icon)

        let linkedCashbacks = state.cashbacks.filter { $0.categoryRaw == rawValue }
        let now = Date()

        if let system = systemCategoryOptions.first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            migrateCategoryPreferences(from: rawValue, to: system.rawValue)
            for cashback in linkedCashbacks {
                cashback.categoryRaw = system.rawValue
                cashback.name = system.displayName
                cashback.updatedAt = now
            }
            modelContext.delete(sourceCategory)
            return saveCategoriesAndCashbacks()
        }

        if let duplicate = state.customCategories.first(where: {
            $0.normalizedName == normalized && $0.categoryID != sourceCustomID
        }) {
            let duplicateRaw = Self.customRawValue(from: duplicate.categoryID)
            migrateCategoryPreferences(from: rawValue, to: duplicateRaw)
            for cashback in linkedCashbacks {
                cashback.categoryRaw = duplicateRaw
                cashback.name = duplicate.name
                cashback.updatedAt = now
            }
            modelContext.delete(sourceCategory)
            return saveCategoriesAndCashbacks()
        }

        sourceCategory.name = trimmed
        sourceCategory.normalizedName = normalized
        sourceCategory.icon = normalizedIcon
        sourceCategory.updatedAt = now

        for cashback in linkedCashbacks {
            cashback.name = trimmed
            cashback.updatedAt = now
        }

        return saveCategoriesAndCashbacks()
    }

    @discardableResult
    func deleteCustomCategory(rawValue: String) -> Bool {
        let fallback = CashbackCategoryOption(
            rawValue: CashbackCategory.other.rawValue,
            displayName: CashbackCategory.other.displayName,
            icon: CashbackCategory.other.icon,
            isCustom: false
        )
        return deleteCustomCategory(rawValue: rawValue, migrateTo: fallback)
    }

    @discardableResult
    func deleteCategory(rawValue: String) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return deleteCustomCategory(rawValue: rawValue)
        }

        guard CashbackCategory(rawValue: rawValue) != nil else { return false }

        let fallbackRaw = CashbackCategory.other.rawValue
        let fallbackName = CashbackCategory.other.displayName
        let now = Date()

        if rawValue != fallbackRaw {
            let linkedCashbacks = state.cashbacks.filter { $0.categoryRaw == rawValue }
            for cashback in linkedCashbacks {
                cashback.categoryRaw = fallbackRaw
                cashback.name = fallbackName
                cashback.updatedAt = now
            }
            migrateCategoryPreferences(from: rawValue, to: fallbackRaw)
        } else {
            removeCategoryPreferences(rawValue: rawValue)
        }

        state.hiddenCategoryRaws.insert(rawValue)
        saveHiddenCategoryRaws()
        return saveCategoriesAndCashbacks()
    }

    @discardableResult
    func deleteCustomCategory(rawValue: String, migrateTo target: CashbackCategoryOption) -> Bool {
        guard let sourceCustomID = Self.customCategoryID(from: rawValue),
              let sourceCategory = state.customCategories.first(where: { $0.categoryID == sourceCustomID }) else {
            return false
        }

        let safeTarget: CashbackCategoryOption
        if target.rawValue == rawValue {
            safeTarget = CashbackCategoryOption(
                rawValue: CashbackCategory.other.rawValue,
                displayName: CashbackCategory.other.displayName,
                icon: CashbackCategory.other.icon,
                isCustom: false
            )
        } else {
            safeTarget = target
        }

        let now = Date()
        let linkedCashbacks = state.cashbacks.filter { $0.categoryRaw == rawValue }
        for cashback in linkedCashbacks {
            cashback.categoryRaw = safeTarget.rawValue
            cashback.name = safeTarget.displayName
            cashback.updatedAt = now
        }

        if safeTarget.rawValue == rawValue {
            removeCategoryPreferences(rawValue: rawValue)
        } else {
            migrateCategoryPreferences(from: rawValue, to: safeTarget.rawValue)
        }
        modelContext.delete(sourceCategory)
        return saveCategoriesAndCashbacks()
    }

    private func shiftSelectedMonth(by delta: Int) {
        let calendar = Calendar.current
        let selected = calendar.date(
            from: calendar.dateComponents([.year, .month], from: state.selectedMonth)
        ) ?? state.selectedMonth
        let minMonth = minSelectableMonth
        let maxMonth = maxSelectableMonth
        let candidate = calendar.date(byAdding: .month, value: delta, to: selected) ?? selected
        state.selectedMonth = min(max(candidate, minMonth), maxMonth)
        applyFilters()
    }
    
    // MARK: - Private Methods
    
    private func loadCashbacks() {
        let descriptor = FetchDescriptor<Cashback>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let cashbacks = try? modelContext.fetch(descriptor) {
            state.cashbacks = cashbacks
            migrateLegacyPinnedCategoriesIfNeeded()
            sanitizePinnedCashbackKeys()
            normalizeMissingMonthKeys()
            applyFilters()
        }
    }

    private func loadCustomCategories() {
        let descriptor = FetchDescriptor<CashbackCustomCategory>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let categories = try? modelContext.fetch(descriptor) {
            state.customCategories = categories
            sanitizeStoredCategoryPreferences()
        }
    }

    @discardableResult
    private func saveCategoriesAndCashbacks() -> Bool {
        do {
            try modelContext.save()
            loadCustomCategories()
            loadCashbacks()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to save custom cashback categories: \(error.localizedDescription)")
            return false
        }
    }

    private func normalizeMissingMonthKeys() {
        var hasChanges = false
        for cashback in state.cashbacks {
            if Cashback.startOfMonth(for: cashback.monthKey) == nil {
                cashback.monthKey = Cashback.monthKey(for: cashback.createdAt)
                cashback.updatedAt = Date()
                hasChanges = true
            }
        }

        guard hasChanges else { return }
        do {
            try modelContext.save()
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to normalize cashback month keys: \(error.localizedDescription)")
        }
    }
    
    /// Очищает несуществующие cardIDs из кешбэков.
    ///
    /// Валидный набор — объединение легаси-карт (`cardUniqueID`) и core-счетов (`Account.id.uuidString`)
    /// (6b Путь B, Ф5c.4): `state.availableAccounts` уже содержит оба мира. Так живое правило,
    /// чей `cardID` был переписан на core-UUID мигратором (`remapCashbackCardIDs`, Ф5b), не считается
    /// «несуществующим» и не обнуляется.
    private func cleanInvalidCardIDs(in cashbacks: [Cashback]) {
        let validIDs = Set(state.availableAccounts.compactMap(\.cardID))

        AppLogger.log(.info, category: "Cashback", "Available \(state.availableAccounts.count) accounts with unique IDs")

        var hasChanges = false

        for cashback in cashbacks {
            let originalCount = cashback.cardIDs.count
            let validCardIDs = cashback.cardIDs.compactMap { cardIDString -> String? in
                if validIDs.contains(cardIDString) {
                    return cardIDString
                }

                AppLogger.log(.info, category: "Cashback", "Invalid cardID '\(cardIDString.prefix(50))...' in cashback '\(cashback.displayCategoryName)'")
                return nil
            }
            
            if validCardIDs.count != originalCount || validCardIDs != cashback.cardIDs {
                AppLogger.log(.info, category: "Cashback", "Updating cardIDs for cashback '\(cashback.displayCategoryName)'. Original count: \(originalCount), Valid count: \(validCardIDs.count)")
                cashback.cardIDs = validCardIDs
                cashback.updatedAt = Date()
                hasChanges = true
            }
        }
        
        if hasChanges {
            do {
                try modelContext.save()
                AppLogger.log(.info, category: "Cashback", "Cleaned invalid card IDs and saved")
            } catch {
                AppLogger.log(.error, category: "Cashback", "Failed to clean invalid card IDs: \(error.localizedDescription)")
            }
        } else {
            AppLogger.log(.info, category: "Cashback", "No invalid card IDs found")
        }
    }
    
    private func loadCards() {
        let oldCardIDs = Set(state.availableAccounts.compactMap(\.cardID))
        state.availableAccounts = buildAvailableAccounts()
        let newCardIDs = Set(state.availableAccounts.compactMap(\.cardID))
        
        // Очищаем несуществующие cardIDs если:
        // 1. Карты действительно удалены (список уменьшился)
        // 2. Или это первый запуск и нужно проверить все связи
        let cardsWereDeleted = !oldCardIDs.isEmpty && oldCardIDs != newCardIDs && newCardIDs.isSubset(of: oldCardIDs)
        let isFirstLoad = oldCardIDs.isEmpty && !newCardIDs.isEmpty && !state.cashbacks.isEmpty
        
        if (cardsWereDeleted || isFirstLoad) && !state.cashbacks.isEmpty {
            // Карты были удалены или это первый запуск - очищаем несуществующие ссылки
            cleanInvalidCardIDs(in: state.cashbacks)
            // Обновляем список кешбэков после очистки
            let descriptor = FetchDescriptor<Cashback>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            if let cashbacks = try? modelContext.fetch(descriptor) {
                state.cashbacks = cashbacks
                normalizeMissingMonthKeys()
                sanitizePinnedCashbackKeys()
                applyFilters()
            }
        }
    }
    
    /// Единый источник счетов-целей кэшбэка: карты легаси (`CardManager`) ∪ денежные счета
    /// нового ядра. Переиспользует резолвер Cashflow (`.expense`, без фильтра валюты — кэшбэк
    /// не ограничивает валюту на этапе выбора). После сноса легаси-карт (Ф5c.6) первый источник
    /// станет пустым и останутся только core-счета — сигнатура не меняется.
    private func buildAvailableAccounts() -> [CashflowSelectableAccount] {
        CashflowSelectableAccountResolver.options(
            cards: CardManager.shared.getAllCards(),
            investments: [],
            linkedInvestmentIDs: [],
            transactionType: .expense,
            currency: "",
            newCoreAccounts: cashLikeCoreAccounts(),
            coreFavoriteAccountIDs: (try? AccountAppearanceStore(context: modelContext).favoriteAccountIDs()) ?? []
        )
    }

    /// Активные денежные счета ядра (cash/debitCard/bankAccount) — те же kind, что участвуют в
    /// Cashflow-пикере (`CashflowViewModel.newCoreAccountsForCashflowPicker`). Вклады/кредиты/долги/
    /// рынок не являются целью кэшбэка.
    private func cashLikeCoreAccounts() -> [Account] {
        let cashLikeKinds: Set<String> = [
            AccountKind.cash.rawValue, AccountKind.debitCard.rawValue, AccountKind.bankAccount.rawValue
        ]
        guard let accounts = try? modelContext.fetch(FetchDescriptor<Account>()) else { return [] }
        let today = now()
        return accounts.filter { cashLikeKinds.contains($0.kindRaw) && $0.participates(on: today) }
    }

    private func applyFilters() {
        let selectedMonthKey = Cashback.monthKey(for: state.selectedMonth)
        state.visibleCashbacks = state.cashbacks
            .filter { $0.monthKey == selectedMonthKey }
            .sorted { lhs, rhs in
                let lhsFavorite = state.favoriteCategoryRaws.contains(
                    canonicalFavoriteRaw(for: lhs.categoryRaw, fallbackName: lhs.name)
                )
                let rhsFavorite = state.favoriteCategoryRaws.contains(
                    canonicalFavoriteRaw(for: rhs.categoryRaw, fallbackName: rhs.name)
                )
                if lhsFavorite != rhsFavorite { return lhsFavorite && !rhsFavorite }
                let lhsPinned = isPinnedCashback(lhs)
                let rhsPinned = isPinnedCashback(rhs)
                if lhsPinned != rhsPinned { return lhsPinned && !rhsPinned }
                if lhs.percentage != rhs.percentage { return lhs.percentage > rhs.percentage }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
    
    private func deleteCashback(_ cashback: Cashback) {
        state.pinnedCashbackKeys.remove(pinnedCashbackKey(for: cashback))
        savePinnedCashbackKeys()
        modelContext.delete(cashback)
        
        do {
            try modelContext.save()
            loadCashbacks()
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to delete cashback: \(error.localizedDescription)")
        }
    }
    
    private func updateCashback(category: CashbackCategory, percentage: Double, cardIDs: [String]) {
        // Фильтруем только существующие карты перед сохранением
        // Используем cardUniqueID для стабильной идентификации
        let availableUniqueIDs = Set(state.availableAccounts.compactMap(\.cardID))
        let selectedMonthKey = Cashback.monthKey(for: state.selectedMonth)
        let validCardIDs = cardIDs.compactMap { cardIDString -> String? in
            if availableUniqueIDs.contains(cardIDString) {
                return cardIDString
            }
            return nil
        }
        
        if let existing = state.editingCashback {
            // Обновляем существующий кешбэк
            existing.category = category
            existing.name = category.displayName
            existing.percentage = percentage
            existing.cardIDs = validCardIDs
            existing.monthKey = selectedMonthKey
            existing.updatedAt = Date()
        } else {
            // Создаем новый кешбэк (name будет пустым, используется только категория)
            let newCashback = Cashback(
                name: category.displayName,
                category: category,
                percentage: percentage,
                cardIDs: validCardIDs,
                monthKey: selectedMonthKey
            )
            modelContext.insert(newCashback)
        }
        
        do {
            try modelContext.save()
            loadCashbacks()
            state.showCashbackEditor = false
            state.editingCashback = nil
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to save cashback: \(error.localizedDescription)")
        }
    }
    
    /// Получить счёт-цель кэшбэка по ID (легаси-карта или core-счёт — единый список).
    func getAccount(byID cardID: String?) -> CashflowSelectableAccount? {
        guard let cardID = cardID else { return nil }
        return state.availableAccounts.first(where: { $0.cardID == cardID })
    }

    /// Получить счета, привязанные к кэшбэку (несуществующие отфильтровываются).
    func getCardsForCashback(_ cashback: Cashback) -> [CashflowSelectableAccount] {
        cashback.cardIDs.compactMap { getAccount(byID: $0) }
    }

    func projectedCategoryCountForMonth(
        cardID: String,
        newCategoryRaws: Set<String>
    ) -> Int {
        let monthKey = Cashback.monthKey(for: state.selectedMonth)
        let monthCashbacks = state.cashbacks.filter { $0.monthKey == monthKey }
        var categorySet: Set<String> = []

        for cashback in monthCashbacks {
            if cashback.cardIDs.contains(cardID) {
                if newCategoryRaws.contains(cashback.categoryRaw) {
                    categorySet.insert(cashback.categoryRaw)
                } else {
                    let remainingCardIDs = cashback.cardIDs.filter { $0 != cardID }
                    if !remainingCardIDs.isEmpty {
                        categorySet.insert(cashback.categoryRaw)
                    }
                }
            } else {
                categorySet.insert(cashback.categoryRaw)
            }
        }

        for raw in newCategoryRaws {
            categorySet.insert(raw)
        }

        return categorySet.count
    }

    private static func customRawValue(from categoryID: String) -> String {
        "\(Cashback.customCategoryPrefix)\(categoryID)"
    }

    private static func customCategoryID(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(Cashback.customCategoryPrefix) else { return nil }
        return String(rawValue.dropFirst(Cashback.customCategoryPrefix.count))
    }

    /// Defense-in-depth против дублей `CashbackCustomCategory.categoryID` (та же уязвимость,
    /// что была у `CashflowCustomCategory`, см. `CashflowCategoryService.dedupedCustomCategories`).
    /// `id` у `CashbackCategoryOption` — это `rawValue` ("custom:<categoryID>"), поэтому два
    /// объекта с одним `categoryID` дают одинаковый `id` и валят `ForEach`/`LazyVGrid`
    /// (`Fatal error: Duplicate values for key`). `DataIntegrityCleaner` вычищает такие дубли
    /// из стора при старте — это последний рубеж на случай, если дубль всё же просочился в
    /// текущую сессию (например, CloudKit merge случился уже после того, как патч отработал).
    /// Побеждает объект с более поздним `updatedAt` — то же правило, что в `DataIntegrityCleaner`.
    static func dedupedCustomCategories(_ categories: [CashbackCustomCategory]) -> [CashbackCustomCategory] {
        var winners: [String: CashbackCustomCategory] = [:]
        var order: [String] = []
        for category in categories {
            if let existing = winners[category.categoryID] {
                if category.updatedAt >= existing.updatedAt {
                    winners[category.categoryID] = category
                }
                AppLogger.log(.warning, category: "Cashback", "Duplicate CashbackCustomCategory categoryID=\(category.categoryID) обнаружен в customCategoryOptions — оставлен один экземпляр")
            } else {
                winners[category.categoryID] = category
                order.append(category.categoryID)
            }
        }
        return order.compactMap { winners[$0] }
    }

    private var systemCategoryOptions: [CashbackCategoryOption] {
        CashbackCategory.allCases.map {
            CashbackCategoryOption(
                rawValue: $0.rawValue,
                displayName: $0.displayName,
                icon: $0.icon,
                isCustom: false
            )
        }
    }

    private var customCategoryOptions: [CashbackCategoryOption] {
        Self.dedupedCustomCategories(state.customCategories).map {
            CashbackCategoryOption(
                rawValue: Self.customRawValue(from: $0.categoryID),
                displayName: $0.name,
                icon: resolvedIcon(for: $0.name, storedIcon: $0.icon),
                isCustom: true
            )
        }
    }

    private func presentedFavoriteCategoryOption(for option: CashbackCategoryOption) -> CashbackCategoryOption {
        let canonicalRaw = canonicalFavoriteRaw(for: option.rawValue, fallbackName: option.displayName)
        guard canonicalRaw != option.rawValue,
              let system = CashbackCategory(rawValue: canonicalRaw) else {
            return option
        }

        return CashbackCategoryOption(
            rawValue: system.rawValue,
            displayName: system.displayName,
            icon: system.icon,
            isCustom: false
        )
    }

    private func preferredFavoriteCategoryOption(
        lhs: CashbackCategoryOption,
        rhs: CashbackCategoryOption
    ) -> CashbackCategoryOption {
        if lhs.isCustom != rhs.isCustom {
            return lhs.isCustom ? rhs : lhs
        }
        if lhs.displayName.count != rhs.displayName.count {
            return lhs.displayName.count < rhs.displayName.count ? lhs : rhs
        }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending ? lhs : rhs
    }

    private func resolvedIcon(for categoryName: String, storedIcon: String) -> String {
        let normalizedStoredIcon = CashbackCustomCategory.normalizeIcon(storedIcon)
        guard normalizedStoredIcon == CashbackCustomCategory.defaultIcon,
              let resolvedSystemRaw = importedCategoryResolver.resolveSystemCategoryRaw(for: categoryName),
              let resolvedSystem = CashbackCategory(rawValue: resolvedSystemRaw) else {
            return normalizedStoredIcon
        }
        return resolvedSystem.icon
    }

    @discardableResult
    func setCategoryHidden(rawValue: String, isHidden: Bool) -> Bool {
        guard CashbackCategory(rawValue: rawValue) != nil else { return false }
        guard rawValue != CashbackCategory.other.rawValue || !isHidden else { return false }

        if isHidden {
            state.hiddenCategoryRaws.insert(rawValue)
            let canonicalRaw = canonicalFavoriteRaw(for: rawValue)
            if state.favoriteCategoryRaws.contains(canonicalRaw) {
                state.favoriteCategoryRaws.remove(canonicalRaw)
                saveFavoriteCategoryRaws()
            }
        } else {
            state.hiddenCategoryRaws.remove(rawValue)
        }

        saveHiddenCategoryRaws()
        applyFilters()
        return true
    }

    private func canonicalFavoriteRaw(for rawValue: String, fallbackName: String = "") -> String {
        if CashbackCategory(rawValue: rawValue) != nil {
            return rawValue
        }

        if let customID = Self.customCategoryID(from: rawValue),
           let custom = state.customCategories.first(where: { $0.categoryID == customID }),
           let resolved = importedCategoryResolver.resolveSystemCategoryRaw(for: custom.name) {
            return resolved
        }

        let safeFallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let resolved = importedCategoryResolver.resolveSystemCategoryRaw(for: safeFallbackName) {
            return resolved
        }

        return rawValue
    }

    private func updateCashbacksForCard(
        cardID: String,
        cashbacks: [(categoryRaw: String, categoryName: String, percentage: Double)]
    ) {
        let validCashbacks = cashbacks.filter { $0.percentage > 0 }

        // Проверяем, что счёт существует
        guard let account = getAccount(byID: cardID) else { return }
        let validCardID = account.cardID ?? cardID
        let selectedMonthKey = Cashback.monthKey(for: state.selectedMonth)

        let validCategoryRaws = Set(validCashbacks.map(\.categoryRaw))

        // Синхронизируем удаленные в редакторе категории: убираем карту из старых связей.
        let existingForCard = state.cashbacks.filter { cashback in
            cashback.monthKey == selectedMonthKey && cashback.cardIDs.contains(validCardID)
        }
        for cashback in existingForCard where !validCategoryRaws.contains(cashback.categoryRaw) {
            cashback.cardIDs.removeAll { $0 == validCardID }
            if cashback.cardIDs.isEmpty {
                modelContext.delete(cashback)
            } else {
                cashback.updatedAt = Date()
            }
        }

        // Создаем кэшбеки для выбранной карты
        for (categoryRaw, categoryName, percentage) in validCashbacks {
            // Проверяем, не существует ли уже такой кэшбек для этой карты
            let existingCashback = state.cashbacks.first { cashback in
                cashback.categoryRaw == categoryRaw &&
                cashback.monthKey == selectedMonthKey &&
                cashback.cardIDs.contains(validCardID)
            }
            
            if let existing = existingCashback {
                // Обновляем существующий кэшбэк, добавляя карту если её нет
                if !existing.cardIDs.contains(validCardID) {
                    existing.cardIDs.append(validCardID)
                }
                existing.categoryRaw = categoryRaw
                existing.name = categoryName
                existing.monthKey = selectedMonthKey
                existing.percentage = percentage
                existing.updatedAt = Date()
            } else {
                // Создаем новый кэшбэк
                let newCashback = Cashback(
                    name: categoryName,
                    categoryRaw: categoryRaw,
                    percentage: percentage,
                    cardIDs: [validCardID],
                    monthKey: selectedMonthKey
                )
                modelContext.insert(newCashback)
            }
        }
        
        do {
            try modelContext.save()
            loadCashbacks()
            state.showCashbackEditor = false
            state.editingCashback = nil
        } catch {
            AppLogger.log(.error, category: "Cashback", "Failed to save cashbacks: \(error.localizedDescription)")
        }
    }

    private func toggleFavoriteCategory(rawValue: String) {
        let canonicalRaw = canonicalFavoriteRaw(for: rawValue)
        if state.favoriteCategoryRaws.contains(canonicalRaw) {
            state.favoriteCategoryRaws.remove(canonicalRaw)
        } else {
            state.favoriteCategoryRaws.insert(canonicalRaw)
            state.pinnedCashbackKeys = Set(
                state.pinnedCashbackKeys.filter { key in
                    canonicalFavoriteRaw(for: keyCategoryRaw(from: key)) != canonicalRaw
                }
            )
            savePinnedCashbackKeys()
        }
        saveFavoriteCategoryRaws()
        applyFilters()
    }

    private func loadFavoriteCategoryRaws() -> Set<String> {
        let stored = defaults.array(forKey: Self.favoriteCategoryRawsKey) as? [String] ?? []
        return Set(stored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func saveFavoriteCategoryRaws() {
        defaults.set(Array(state.favoriteCategoryRaws).sorted(), forKey: Self.favoriteCategoryRawsKey)
    }

    private func togglePinnedCashback(_ cashback: Cashback) {
        if state.favoriteCategoryRaws.contains(
            canonicalFavoriteRaw(for: cashback.categoryRaw, fallbackName: cashback.name)
        ) {
            return
        }
        let key = pinnedCashbackKey(for: cashback)
        if state.pinnedCashbackKeys.contains(key) {
            state.pinnedCashbackKeys.remove(key)
        } else {
            state.pinnedCashbackKeys.insert(key)
        }
        savePinnedCashbackKeys()
        applyFilters()
    }

    private func loadPinnedCashbackKeys() -> Set<String> {
        let stored = defaults.array(forKey: Self.pinnedCashbackKeysKey) as? [String] ?? []
        return Set(stored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func savePinnedCashbackKeys() {
        defaults.set(Array(state.pinnedCashbackKeys).sorted(), forKey: Self.pinnedCashbackKeysKey)
    }

    private func loadHiddenCategoryRaws() -> Set<String> {
        let stored = defaults.array(forKey: Self.hiddenCategoryRawsKey) as? [String] ?? []
        return Set(stored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func saveHiddenCategoryRaws() {
        defaults.set(Array(state.hiddenCategoryRaws).sorted(), forKey: Self.hiddenCategoryRawsKey)
    }

    private func migrateCategoryPreferences(from sourceRaw: String, to targetRaw: String) {
        let canonicalSourceRaw = canonicalFavoriteRaw(for: sourceRaw)
        let canonicalTargetRaw = canonicalFavoriteRaw(for: targetRaw)
        guard canonicalSourceRaw != canonicalTargetRaw else { return }
        let hadFavorite = state.favoriteCategoryRaws.remove(canonicalSourceRaw) != nil

        if hadFavorite {
            state.favoriteCategoryRaws.insert(canonicalTargetRaw)
        }

        saveFavoriteCategoryRaws()
    }

    private func removeCategoryPreferences(rawValue: String) {
        let canonicalRaw = canonicalFavoriteRaw(for: rawValue)
        let hadFavorite = state.favoriteCategoryRaws.remove(canonicalRaw) != nil
        let hadPinned = !state.pinnedCashbackKeys.filter({
            canonicalFavoriteRaw(for: keyCategoryRaw(from: $0)) == canonicalRaw
        }).isEmpty
        state.pinnedCashbackKeys = Set(
            state.pinnedCashbackKeys.filter { canonicalFavoriteRaw(for: keyCategoryRaw(from: $0)) != canonicalRaw }
        )
        guard hadFavorite || hadPinned else { return }
        saveFavoriteCategoryRaws()
        savePinnedCashbackKeys()
    }

    private func sanitizeStoredCategoryPreferences() {
        let allowedRaws = Set(
            (systemCategoryOptions.map(\.rawValue) + customCategoryOptions.map(\.rawValue))
                .map { canonicalFavoriteRaw(for: $0) }
        )
        let sanitizedHidden = Set(state.hiddenCategoryRaws.filter { allowedRaws.contains($0) })
        let sanitizedFavorites = Set(
            state.favoriteCategoryRaws
                .map { canonicalFavoriteRaw(for: $0) }
                .filter { allowedRaws.contains($0) }
        )
        let sanitizedPinned = Set(
            state.pinnedCashbackKeys.filter { key in
                let raw = canonicalFavoriteRaw(for: keyCategoryRaw(from: key))
                return allowedRaws.contains(raw) && !sanitizedFavorites.contains(raw)
            }
        )

        let hiddenChanged = sanitizedHidden != state.hiddenCategoryRaws
        let favoritesChanged = sanitizedFavorites != state.favoriteCategoryRaws
        let pinnedChanged = sanitizedPinned != state.pinnedCashbackKeys
        guard hiddenChanged || favoritesChanged || pinnedChanged else { return }

        state.hiddenCategoryRaws = sanitizedHidden
        state.favoriteCategoryRaws = sanitizedFavorites
        state.pinnedCashbackKeys = sanitizedPinned
        saveHiddenCategoryRaws()
        saveFavoriteCategoryRaws()
        savePinnedCashbackKeys()
    }

    private func pinnedCashbackKey(for cashback: Cashback) -> String {
        let cardsKey = cashback.cardIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: ",")
        return "\(cashback.monthKey)|\(cashback.categoryRaw)|\(cardsKey)"
    }

    private func keyCategoryRaw(from key: String) -> String {
        let parts = key.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return key }
        return String(parts[1])
    }

    private func sanitizePinnedCashbackKeys() {
        let existingKeys = Set(state.cashbacks.map { pinnedCashbackKey(for: $0) })
        let sanitized = Set(state.pinnedCashbackKeys.filter { existingKeys.contains($0) })
        guard sanitized != state.pinnedCashbackKeys else { return }
        state.pinnedCashbackKeys = sanitized
        savePinnedCashbackKeys()
    }

    private func migrateLegacyPinnedCategoriesIfNeeded() {
        guard defaults.object(forKey: Self.legacyPinnedCategoryRawsKey) != nil else { return }
        let legacyStored = defaults.array(forKey: Self.legacyPinnedCategoryRawsKey) as? [String] ?? []
        let legacyRaws = Set(legacyStored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })

        if legacyRaws.isEmpty {
            defaults.removeObject(forKey: Self.legacyPinnedCategoryRawsKey)
            return
        }

        var migrated = state.pinnedCashbackKeys
        let groupedByMonthAndCategory = Dictionary(grouping: state.cashbacks.filter { legacyRaws.contains($0.categoryRaw) }) {
            "\($0.monthKey)|\($0.categoryRaw)"
        }

        for group in groupedByMonthAndCategory.values {
            guard let winner = group.sorted(by: { lhs, rhs in
                if lhs.percentage != rhs.percentage { return lhs.percentage > rhs.percentage }
                return lhs.updatedAt > rhs.updatedAt
            }).first else { continue }
            migrated.insert(pinnedCashbackKey(for: winner))
        }

        state.pinnedCashbackKeys = migrated
        savePinnedCashbackKeys()
        defaults.removeObject(forKey: Self.legacyPinnedCategoryRawsKey)
    }
}
