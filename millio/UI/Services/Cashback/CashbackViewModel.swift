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
    var availableCards: [Card] = []

    /// Пользовательские категории кешбэка
    var customCategories: [CashbackCustomCategory] = []

    /// Выбранный месяц на экране кешбэка
    var selectedMonth: Date = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()

    /// Избранные категории кешбэка (raw keys)
    var favoriteCategoryRaws: Set<String> = []

    /// Закрепленные категории кешбэка (raw keys)
    var pinnedCategoryRaws: Set<String> = []
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
    case togglePinnedCategory(rawValue: String)
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
    private static let pinnedCategoryRawsKey = "cashback.pinned_category_raws"
    
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
        self.state.pinnedCategoryRaws = loadPinnedCategoryRaws()
        // Инициализируем CardManager
        CardManager.shared.setup(modelContext: modelContext)
        // Сначала загружаем карты, потом кешбэки, чтобы правильно проверить связи
        loadCards()
        loadCustomCategories()
        loadCashbacks()
        
        #if DEBUG
        AppLogger.log(.debug, category: "Cashback", "Loaded \(state.availableCards.count) cards, \(state.cashbacks.count) cashbacks")
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

        case .togglePinnedCategory(let rawValue):
            togglePinnedCategory(rawValue: rawValue)
            
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

    func categoryOptions(matching query: String = "") -> [CashbackCategoryOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let allOptions = systemCategoryOptions + customCategoryOptions

        guard !trimmedQuery.isEmpty else { return allOptions }

        return allOptions.filter { option in
            option.displayName.localizedCaseInsensitiveContains(trimmedQuery)
        }
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
                icon: custom.icon,
                isCustom: true
            )
        }

        let safeFallbackName = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        return CashbackCategoryOption(
            rawValue: raw,
            displayName: safeFallbackName.isEmpty ? CashbackCategory.other.displayName : safeFallbackName,
            icon: CashbackCustomCategory.defaultIcon,
            isCustom: true
        )
    }

    func categoryOptionForImportedName(_ name: String) -> CashbackCategoryOption {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return categoryOption(for: CashbackCategory.other.rawValue)
        }

        if let systemRaw = importedCategoryResolver.resolveSystemCategoryRaw(for: trimmed) {
            return categoryOption(for: systemRaw, fallbackName: trimmed)
        }

        if let custom = createCustomCategory(trimmed) {
            return custom
        }

        return categoryOption(for: CashbackCategory.other.rawValue, fallbackName: trimmed)
    }

    func isFavoriteCategory(rawValue: String) -> Bool {
        state.favoriteCategoryRaws.contains(rawValue)
    }

    func isPinnedCategory(rawValue: String) -> Bool {
        state.pinnedCategoryRaws.contains(rawValue)
    }

    var selectedMonthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: state.selectedMonth).capitalized
    }

    var maxSelectableMonth: Date {
        Calendar.current.date(
            from: Calendar.current.dateComponents([.year, .month], from: now())
        ) ?? now()
    }

    func canMoveMonthForward() -> Bool {
        let calendar = Calendar.current
        let selected = calendar.date(
            from: calendar.dateComponents([.year, .month], from: state.selectedMonth)
        ) ?? state.selectedMonth
        let current = maxSelectableMonth
        return selected < current
    }

    @discardableResult
    func createCustomCategory(_ name: String, icon: String = CashbackCustomCategory.defaultIcon) -> CashbackCategoryOption? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let normalizedIcon = CashbackCustomCategory.normalizeIcon(icon)

        if let systemMatch = systemCategoryOptions.first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return systemMatch
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

        modelContext.delete(sourceCategory)
        return saveCategoriesAndCashbacks()
    }

    private func shiftSelectedMonth(by delta: Int) {
        let calendar = Calendar.current
        let selected = calendar.date(
            from: calendar.dateComponents([.year, .month], from: state.selectedMonth)
        ) ?? state.selectedMonth
        let current = maxSelectableMonth
        let candidate = calendar.date(byAdding: .month, value: delta, to: selected) ?? selected
        state.selectedMonth = min(candidate, current)
        applyFilters()
    }
    
    // MARK: - Private Methods
    
    private func loadCashbacks() {
        let descriptor = FetchDescriptor<Cashback>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let cashbacks = try? modelContext.fetch(descriptor) {
            state.cashbacks = cashbacks
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
    
    /// Очищает несуществующие cardIDs из кешбэков
    private func cleanInvalidCardIDs(in cashbacks: [Cashback]) {
        let cardUniqueIDMap: [String: Card] = Dictionary(
            state.availableCards.map { ($0.cardUniqueID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        AppLogger.log(.info, category: "Cashback", "Available \(state.availableCards.count) cards with unique IDs")
        
        var hasChanges = false
        
        for cashback in cashbacks {
            let originalCount = cashback.cardIDs.count
            let validCardIDs = cashback.cardIDs.compactMap { cardIDString -> String? in
                if let card = cardUniqueIDMap[cardIDString] {
                    return card.cardUniqueID
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
        let oldCardIDs = Set(state.availableCards.map(\.cardUniqueID))
        state.availableCards = CardManager.shared.getAllCards()
        let newCardIDs = Set(state.availableCards.map(\.cardUniqueID))
        
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
                applyFilters()
            }
        }
    }
    
    private func applyFilters() {
        let selectedMonthKey = Cashback.monthKey(for: state.selectedMonth)
        state.visibleCashbacks = state.cashbacks
            .filter { $0.monthKey == selectedMonthKey }
            .sorted { lhs, rhs in
                let lhsFavorite = state.favoriteCategoryRaws.contains(lhs.categoryRaw)
                let rhsFavorite = state.favoriteCategoryRaws.contains(rhs.categoryRaw)
                if lhsFavorite != rhsFavorite { return lhsFavorite && !rhsFavorite }
                let lhsPinned = state.pinnedCategoryRaws.contains(lhs.categoryRaw)
                let rhsPinned = state.pinnedCategoryRaws.contains(rhs.categoryRaw)
                if lhsPinned != rhsPinned { return lhsPinned && !rhsPinned }
                if lhs.percentage != rhs.percentage { return lhs.percentage > rhs.percentage }
                return lhs.updatedAt > rhs.updatedAt
            }
    }
    
    private func deleteCashback(_ cashback: Cashback) {
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
        let availableUniqueIDs = Set(state.availableCards.map { $0.cardUniqueID })
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
    
    /// Получить карту по ID
    func getCard(byID cardID: String?) -> Card? {
        guard let cardID = cardID else { return nil }
        return state.availableCards.first(where: { $0.cardUniqueID == cardID })
    }
    
    /// Получить карты, которые можно использовать для получения кешбэка
    func getCardsForCashback(_ cashback: Cashback) -> [Card] {
        // Всегда показываем только привязанные карты (если они есть)
        // Фильтруем несуществующие карты
        return cashback.cardIDs.compactMap { cardID in
            getCard(byID: cardID)
        }
    }

    private static func customRawValue(from categoryID: String) -> String {
        "\(Cashback.customCategoryPrefix)\(categoryID)"
    }

    private static func customCategoryID(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(Cashback.customCategoryPrefix) else { return nil }
        return String(rawValue.dropFirst(Cashback.customCategoryPrefix.count))
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
        state.customCategories.map {
            CashbackCategoryOption(
                rawValue: Self.customRawValue(from: $0.categoryID),
                displayName: $0.name,
                icon: $0.icon,
                isCustom: true
            )
        }
    }

    private func updateCashbacksForCard(
        cardID: String,
        cashbacks: [(categoryRaw: String, categoryName: String, percentage: Double)]
    ) {
        // Фильтруем только валидные кэшбеки (с процентом > 0)
        let validCashbacks = cashbacks.filter { $0.percentage > 0 }
        
        guard !validCashbacks.isEmpty else { return }
        
        // Проверяем, что карта существует
        guard let card = getCard(byID: cardID) else { return }
        let validCardID = card.cardUniqueID
        let selectedMonthKey = Cashback.monthKey(for: state.selectedMonth)
        
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
        if state.favoriteCategoryRaws.contains(rawValue) {
            state.favoriteCategoryRaws.remove(rawValue)
        } else {
            state.favoriteCategoryRaws.insert(rawValue)
            state.pinnedCategoryRaws.remove(rawValue)
            savePinnedCategoryRaws()
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

    private func togglePinnedCategory(rawValue: String) {
        if state.favoriteCategoryRaws.contains(rawValue) {
            return
        }
        if state.pinnedCategoryRaws.contains(rawValue) {
            state.pinnedCategoryRaws.remove(rawValue)
        } else {
            state.pinnedCategoryRaws.insert(rawValue)
        }
        savePinnedCategoryRaws()
        applyFilters()
    }

    private func loadPinnedCategoryRaws() -> Set<String> {
        let stored = defaults.array(forKey: Self.pinnedCategoryRawsKey) as? [String] ?? []
        return Set(stored.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
    }

    private func savePinnedCategoryRaws() {
        defaults.set(Array(state.pinnedCategoryRaws).sorted(), forKey: Self.pinnedCategoryRawsKey)
    }
}
