//
//  CashflowCategoryService.swift
//  millio
//
//  Создан в рамках Phase 4 декомпозиции CashflowViewModel.
//  Отвечает за CRUD категорий: системные и пользовательские.
//

import Foundation
import SwiftData

// MARK: - CashflowCategoryService

@MainActor
final class CashflowCategoryService {

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let categoryPinPrefs: CashflowCategoryPinPrefs
    let categoryOrderPrefs: CashflowCategoryOrderPrefs
    private let bulkExpenseMerchantPrefs: CashflowBulkExpenseMerchantCategoryPrefs
    private let customCategoryVisibilityPrefs: CashflowCustomCategoryVisibilityPrefs
    private let now: () -> Date

    /// Провайдер пользовательских категорий из CashflowState
    private let customCategoriesProvider: () -> [CashflowCustomCategory]

    /// Провайдер переопределений системных категорий из CashflowState
    private let systemCategoryOverridesProvider: () -> [CashflowSystemCategoryOverride]

    /// Callback после успешного сохранения: перезагружает категории и транзакции в VM
    private let onCategoriesChanged: () -> Void

    // MARK: - Init

    init(
        modelContext: ModelContext,
        categoryPinPrefs: CashflowCategoryPinPrefs,
        categoryOrderPrefs: CashflowCategoryOrderPrefs = CashflowCategoryOrderPrefs(),
        bulkExpenseMerchantPrefs: CashflowBulkExpenseMerchantCategoryPrefs,
        customCategoryVisibilityPrefs: CashflowCustomCategoryVisibilityPrefs = CashflowCustomCategoryVisibilityPrefs(),
        now: @escaping () -> Date,
        customCategoriesProvider: @escaping () -> [CashflowCustomCategory],
        systemCategoryOverridesProvider: @escaping () -> [CashflowSystemCategoryOverride],
        onCategoriesChanged: @escaping () -> Void
    ) {
        self.modelContext = modelContext
        self.categoryPinPrefs = categoryPinPrefs
        self.categoryOrderPrefs = categoryOrderPrefs
        self.bulkExpenseMerchantPrefs = bulkExpenseMerchantPrefs
        self.customCategoryVisibilityPrefs = customCategoryVisibilityPrefs
        self.now = now
        self.customCategoriesProvider = customCategoriesProvider
        self.systemCategoryOverridesProvider = systemCategoryOverridesProvider
        self.onCategoriesChanged = onCategoriesChanged
    }

    // MARK: - Load

    func loadCustomCategories() -> [CashflowCustomCategory] {
        let descriptor = FetchDescriptor<CashflowCustomCategory>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func loadSystemCategoryOverrides() -> [CashflowSystemCategoryOverride] {
        let descriptor = FetchDescriptor<CashflowSystemCategoryOverride>()
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Category Options

    func categoryOptions(
        for kind: CashflowCategoryKind,
        matching query: String = "",
        includeHiddenSystem: Bool = false
    ) -> [CashflowCategoryOption] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = systemCategoryOptions(for: kind, includeHidden: includeHiddenSystem) + customCategoryOptions(for: kind, includeHidden: includeHiddenSystem)

        guard !trimmedQuery.isEmpty else { return options }
        return options.filter { option in
            if option.isCustom {
                return option.displayName.localizedCaseInsensitiveContains(trimmedQuery)
            }
            switch kind {
            case .income:
                return IncomeCategory.matchesSearch(rawValue: option.rawValue, query: trimmedQuery)
            case .expense:
                return ExpenseCategoryCatalog.matchesSearch(rawValue: option.rawValue, query: trimmedQuery)
            }
        }
    }

    func orderedCategoryOptions(
        for kind: CashflowCategoryKind,
        matching query: String = "",
        includeHiddenSystem: Bool = false,
        totalsByCategory: [String: Double] = [:]
    ) -> [CashflowCategoryOption] {
        let options = categoryOptions(
            for: kind,
            matching: query,
            includeHiddenSystem: includeHiddenSystem
        )
        if query.trimmingCharacters(in: .whitespaces).isEmpty,
           let customOrder = categoryOrderPrefs.customOrder(for: kind) {
            return Self.sortCategoryOptionsWithCustomOrder(
                options,
                customOrder: customOrder,
                pinnedRawValues: categoryPinPrefs.pinnedRawValues(for: kind)
            )
        }
        return Self.sortCategoryOptions(
            options,
            totalsByCategory: totalsByCategory,
            pinnedRawValues: categoryPinPrefs.pinnedRawValues(for: kind)
        )
    }

    /// Сортирует по пользовательскому порядку; элементы не вошедшие в порядок — в конце по алфавиту.
    static func sortCategoryOptionsWithCustomOrder(
        _ options: [CashflowCategoryOption],
        customOrder: [String],
        pinnedRawValues: Set<String>
    ) -> [CashflowCategoryOption] {
        let orderIndex: [String: Int] = Dictionary(
            uniqueKeysWithValues: customOrder.enumerated().map { ($0.element, $0.offset) }
        )
        return options.sorted { lhs, rhs in
            let lhsPinned = pinnedRawValues.contains(lhs.rawValue)
            let rhsPinned = pinnedRawValues.contains(rhs.rawValue)
            if lhsPinned != rhsPinned { return lhsPinned }

            let li = orderIndex[lhs.rawValue] ?? Int.max
            let ri = orderIndex[rhs.rawValue] ?? Int.max
            if li != ri { return li < ri }

            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    static func sortCategoryOptions(
        _ options: [CashflowCategoryOption],
        totalsByCategory: [String: Double],
        pinnedRawValues: Set<String>
    ) -> [CashflowCategoryOption] {
        options.sorted { lhs, rhs in
            let lhsPinned = pinnedRawValues.contains(lhs.rawValue)
            let rhsPinned = pinnedRawValues.contains(rhs.rawValue)
            if lhsPinned != rhsPinned {
                return lhsPinned && !rhsPinned
            }

            let lhsTotal = totalsByCategory[lhs.rawValue] ?? 0
            let rhsTotal = totalsByCategory[rhs.rawValue] ?? 0
            let lhsHasActivity = lhsTotal > 0.0000001
            let rhsHasActivity = rhsTotal > 0.0000001

            if lhsHasActivity != rhsHasActivity {
                return lhsHasActivity && !rhsHasActivity
            }

            if abs(lhsTotal - rhsTotal) > 0.0000001 {
                return lhsTotal > rhsTotal
            }

            let nameOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
            if nameOrder != .orderedSame {
                return nameOrder == .orderedAscending
            }

            return lhs.rawValue < rhs.rawValue
        }
    }

    // MARK: - Pin

    func isCategoryPinned(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        categoryPinPrefs.isPinned(categoryRaw: rawValue, kind: kind)
    }

    /// Обновляет pin-статус. Возвращает true чтобы VM вызвал objectWillChange.send().
    @discardableResult
    func setCategoryPinned(rawValue: String, kind: CashflowCategoryKind, isPinned: Bool) -> Bool {
        categoryPinPrefs.setPinned(isPinned, categoryRaw: rawValue, kind: kind)
        return true
    }

    // MARK: - Display Helpers

    func categoryOption(for raw: String, kind: CashflowCategoryKind, fallbackName: String = "") -> CashflowCategoryOption {
        let resolvedRaw = canonicalSystemCategoryRaw(for: raw, kind: kind)

        if let system = systemCategoryOption(for: resolvedRaw, kind: kind, includeHidden: true) {
            return system
        }
        if let customID = Self.customCategoryID(from: resolvedRaw),
           let custom = customCategoriesProvider().first(where: { $0.categoryID == customID && $0.kind == kind }) {
            return CashflowCategoryOption(
                rawValue: resolvedRaw,
                displayName: custom.name,
                icon: custom.icon,
                isCustom: true
            )
        }

        let fallback = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultOption = defaultCategoryOption(for: kind)
        return CashflowCategoryOption(
            rawValue: defaultOption.rawValue,
            displayName: fallback.isEmpty ? defaultOption.displayName : fallback,
            icon: defaultOption.icon,
            isCustom: false
        )
    }

    func incomeCategoryDisplayName(for raw: String?) -> String {
        guard let raw else { return CashflowLocalization.uncategorized }
        return categoryOption(for: raw, kind: .income).displayName
    }

    func expenseCategoryDisplayName(for raw: String?) -> String {
        guard let raw else { return CashflowLocalization.uncategorized }
        return categoryOption(for: raw, kind: .expense).displayName
    }

    func incomeCategoryIcon(for raw: String?) -> String {
        guard let raw else { return IncomeCategory.other.icon }
        return categoryOption(for: raw, kind: .income).icon
    }

    func expenseCategoryIcon(for raw: String?) -> String {
        guard let raw else { return ExpenseCategory.other.icon }
        return categoryOption(for: raw, kind: .expense).icon
    }

    // MARK: - Create

    @discardableResult
    func createCustomCategory(
        kind: CashflowCategoryKind,
        name: String,
        icon: String = CashflowCustomCategory.defaultIcon
    ) -> CashflowCategoryOption? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let system = systemCategoryOptions(for: kind, includeHidden: true).first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            return system
        }

        let normalized = CashflowCustomCategory.normalize(trimmed)
        if let existing = customCategoriesProvider().first(where: {
            $0.kind == kind && $0.normalizedName == normalized
        }) {
            return CashflowCategoryOption(
                rawValue: Self.customRawValue(from: existing.categoryID),
                displayName: existing.name,
                icon: existing.icon,
                isCustom: true
            )
        }

        let customCategory = CashflowCustomCategory(
            kind: kind,
            name: trimmed,
            icon: CashflowCustomCategory.normalizeIcon(icon)
        )
        modelContext.insert(customCategory)

        do {
            try modelContext.save()
            onCategoriesChanged()
            return CashflowCategoryOption(
                rawValue: Self.customRawValue(from: customCategory.categoryID),
                displayName: customCategory.name,
                icon: customCategory.icon,
                isCustom: true
            )
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to create custom category: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Rename

    @discardableResult
    func renameCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return renameCustomCategory(rawValue: rawValue, kind: kind, newName: newName, newIcon: newIcon)
        }
        return renameSystemCategory(rawValue: rawValue, kind: kind, newName: newName, newIcon: newIcon)
    }

    @discardableResult
    func renameCustomCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        guard let sourceID = Self.customCategoryID(from: rawValue),
              let sourceCategory = customCategoriesProvider().first(where: { $0.categoryID == sourceID && $0.kind == kind }) else {
            return false
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = CashflowCustomCategory.normalize(trimmed)
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(newIcon ?? sourceCategory.icon)
        let nowDate = Date()

        if let system = systemCategoryOptions(for: kind).first(where: {
            $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            migrateTransactions(fromRaw: rawValue, toRaw: system.rawValue, kind: kind, nowDate: nowDate)
            modelContext.delete(sourceCategory)
            return saveCategoriesAndTransactions()
        }

        if let duplicate = customCategoriesProvider().first(where: {
            $0.kind == kind && $0.normalizedName == normalized && $0.categoryID != sourceID
        }) {
            let duplicateRaw = Self.customRawValue(from: duplicate.categoryID)
            migrateTransactions(fromRaw: rawValue, toRaw: duplicateRaw, kind: kind, nowDate: nowDate)
            modelContext.delete(sourceCategory)
            return saveCategoriesAndTransactions()
        }

        sourceCategory.name = trimmed
        sourceCategory.normalizedName = normalized
        sourceCategory.icon = normalizedIcon
        sourceCategory.updatedAt = nowDate

        return saveCategoriesAndTransactions()
    }

    // MARK: - Delete

    @discardableResult
    func deleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        performCategoryRemoval(rawValue: rawValue, kind: kind, targetRawValue: nil) != nil
    }

    @discardableResult
    func deleteCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String?
    ) -> Bool {
        performCategoryRemoval(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue) != nil
    }

    func performCategoryRemoval(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String?
    ) -> CashflowCategoryMutationUndoAction? {
        if Self.customCategoryID(from: rawValue) != nil {
            return deleteCustomCategory(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue)
        }
        return deleteSystemCategory(rawValue: rawValue, kind: kind, targetRawValue: targetRawValue)
    }

    @discardableResult
    func deleteCustomCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String? = nil
    ) -> CashflowCategoryMutationUndoAction? {
        guard let sourceID = Self.customCategoryID(from: rawValue) else {
            return nil
        }

        let sourceCategory = customCategoriesProvider().first {
            $0.categoryID == sourceID && $0.kind == kind
        } ?? ((try? modelContext.fetch(FetchDescriptor<CashflowCustomCategory>())) ?? []).first {
            $0.categoryID == sourceID && $0.kind == kind
        }

        guard let sourceCategory else { return nil }

        guard let target = validatedDeleteTargetOption(
            sourceRaw: rawValue,
            kind: kind,
            targetRawValue: targetRawValue
        ) else {
            return nil
        }
        let undoAction = makeCategoryMutationUndoAction(
            sourceRaw: rawValue,
            kind: kind,
            target: target,
            sourceCategory: sourceCategory,
            systemOverride: nil,
            isArchive: false
        )
        let nowDate = now()
        migrateTransactions(fromRaw: rawValue, toRaw: target.rawValue, kind: kind, nowDate: nowDate)
        migrateBudgetCategoryLimits(fromRaw: rawValue, toRaw: target.rawValue, kind: kind, nowDate: nowDate)
        categoryPinPrefs.remap(categoryRaw: rawValue, to: target.rawValue, kind: kind)
        customCategoryVisibilityPrefs.removeAll(categoryRaw: rawValue, kind: kind)
        if kind == .expense {
            bulkExpenseMerchantPrefs.remapCategory(from: rawValue, to: target.rawValue)
        }
        modelContext.delete(sourceCategory)

        return saveCategoriesAndTransactions() ? undoAction : nil
    }

    // MARK: - Can Delete

    func canDeleteCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        if Self.customCategoryID(from: rawValue) != nil {
            return customCategoriesProvider().contains {
                Self.customRawValue(from: $0.categoryID) == rawValue && $0.kind == kind
            }
        }

        if isProtectedFallbackCategory(rawValue: rawValue, kind: kind) {
            return false
        }
        return baseSystemCategoryOption(for: rawValue, kind: kind) != nil
    }

    // MARK: - Deletion Preview

    func categoryDeletionPreview(
        rawValue: String,
        kind: CashflowCategoryKind
    ) -> CashflowCategoryDeletionPreview? {
        guard canDeleteCategory(rawValue: rawValue, kind: kind) else {
            return nil
        }

        let sourceOption = categoryOption(for: rawValue, kind: kind)
        let availableTargetOptions = categoryOptions(
            for: kind,
            includeHiddenSystem: true
        ).filter { $0.rawValue != sourceOption.rawValue }

        guard let suggestedTargetOption = availableTargetOptions.first(where: {
            $0.rawValue == fallbackCategoryRaw(for: kind)
        }) ?? availableTargetOptions.first else {
            return nil
        }

        let linked = linkedTransactions(for: rawValue, kind: kind)
        let linkedBudgetLimits = linkedBudgetCategoryLimits(for: rawValue, kind: kind)
        let displayCurrency = (try? modelContext.fetch(FetchDescriptor<CashflowTransaction>()))
            .map { _ in "" } ?? ""
        let totalsByCurrency = Dictionary(grouping: linked, by: \.currency)
            .map { currency, transactions in
                CashflowCategoryDeletionAmountSummary(
                    currency: currency,
                    amount: transactions.reduce(0) { $0 + $1.amount }
                )
            }
            .sorted {
                let lhsIsPrimary = $0.currency == displayCurrency
                let rhsIsPrimary = $1.currency == displayCurrency
                if lhsIsPrimary != rhsIsPrimary {
                    return lhsIsPrimary && !rhsIsPrimary
                }
                return $0.currency.localizedCaseInsensitiveCompare($1.currency) == .orderedAscending
            }

        return CashflowCategoryDeletionPreview(
            rawValue: rawValue,
            kind: kind,
            sourceOption: sourceOption,
            suggestedTargetOption: suggestedTargetOption,
            availableTargetOptions: availableTargetOptions,
            linkedTransactionCount: linked.count,
            linkedBudgetLimitCount: linkedBudgetLimits.count,
            totalsByCurrency: totalsByCurrency
        )
    }

    // MARK: - Undo

    @discardableResult
    func undoCategoryMutation(_ action: CashflowCategoryMutationUndoAction) -> Bool {
        if let customSnapshot = action.customCategorySnapshot {
            restoreCustomCategory(from: customSnapshot)
        }

        restoreSystemCategoryOverride(
            action.systemOverrideSnapshot,
            sourceRaw: action.sourceOption.rawValue,
            kind: action.kind
        )

        for snapshot in action.transactionSnapshots {
            switch action.kind {
            case .income:
                snapshot.transaction.incomeCategoryRaw = snapshot.originalRawValue
            case .expense:
                snapshot.transaction.expenseCategoryRaw = snapshot.originalRawValue
            }
            snapshot.transaction.updatedAt = now()
        }

        restoreBudgetLimitSnapshots(action.budgetLimitSnapshots)
        categoryPinPrefs.replacePinnedRawValues(action.pinnedRawValuesBefore, kind: action.kind)
        if action.kind == .expense, let merchantMappingsBefore = action.merchantMappingsBefore {
            bulkExpenseMerchantPrefs.replaceMappings(merchantMappingsBefore)
        }

        return saveCategoriesAndTransactions()
    }

    // MARK: - System Category Visibility

    @discardableResult
    func setSystemCategoryHidden(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        isHidden: Bool
    ) -> Bool {
        guard let base = baseSystemCategoryOption(for: categoryRaw, kind: kind) else {
            return false
        }
        guard !isProtectedFallbackCategory(rawValue: categoryRaw, kind: kind) || !isHidden else {
            return false
        }

        let nowDate = now()
        if isHidden {
            setSystemCategoryOverride(
                kind: kind,
                categoryRaw: categoryRaw,
                name: base.displayName,
                icon: base.icon,
                isHidden: true,
                nowDate: nowDate
            )
        } else if let override = systemCategoryOverride(for: categoryRaw, kind: kind) {
            if isDefaultSystemOverride(override, base: base, kind: kind) && override.icon == base.icon {
                removeSystemCategoryOverride(kind: kind, categoryRaw: categoryRaw)
            } else {
                override.isHidden = false
                override.updatedAt = nowDate
            }
        }

        return saveCategoriesAndTransactions()
    }

    // MARK: - Static Utilities

    static func customRawValue(from categoryID: String) -> String {
        "\(CashflowTransaction.customCategoryPrefix)\(categoryID)"
    }

    static func customCategoryID(from rawValue: String) -> String? {
        guard rawValue.hasPrefix(CashflowTransaction.customCategoryPrefix) else { return nil }
        return String(rawValue.dropFirst(CashflowTransaction.customCategoryPrefix.count))
    }

    // MARK: - Private: System Categories

    private func systemCategoryRaws(for kind: CashflowCategoryKind) -> [String] {
        switch kind {
        case .income:
            return IncomeCategory.allCases.map(\.rawValue)
        case .expense:
            return ExpenseCategory.allCases.map(\.rawValue)
        }
    }

    func systemCategoryOption(
        for raw: String,
        kind: CashflowCategoryKind,
        includeHidden: Bool = false
    ) -> CashflowCategoryOption? {
        let resolvedRaw = canonicalSystemCategoryRaw(for: raw, kind: kind)

        guard let base = baseSystemCategoryOption(for: resolvedRaw, kind: kind) else {
            return nil
        }
        if let override = systemCategoryOverride(for: resolvedRaw, kind: kind) {
            if override.isHidden && !includeHidden {
                return nil
            }
            return CashflowCategoryOption(
                rawValue: resolvedRaw,
                displayName: resolvedSystemCategoryOverrideName(override, base: base, kind: kind),
                icon: override.icon,
                isCustom: false
            )
        }
        return base
    }

    func systemCategoryOptions(
        for kind: CashflowCategoryKind,
        includeHidden: Bool = false
    ) -> [CashflowCategoryOption] {
        systemCategoryRaws(for: kind).compactMap { raw in
            systemCategoryOption(for: raw, kind: kind, includeHidden: includeHidden)
        }
    }

    func ensureSystemCategoriesVisible(rawValues: [String], kind: CashflowCategoryKind, nowDate: Date) {
        let systemRaws = Set(systemCategoryRaws(for: kind))
        let rawsToReveal = Set(rawValues.map { canonicalSystemCategoryRaw(for: $0, kind: kind) }).intersection(systemRaws)

        guard !rawsToReveal.isEmpty else { return }

        for raw in rawsToReveal {
            guard let existing = systemCategoryOverride(for: raw, kind: kind), existing.isHidden else {
                continue
            }
            existing.isHidden = false
            existing.updatedAt = nowDate
        }
    }

    private func customCategoryOptions(for kind: CashflowCategoryKind, includeHidden: Bool = false) -> [CashflowCategoryOption] {
        let hiddenRaws = includeHidden ? Set<String>() : customCategoryVisibilityPrefs.hiddenRawValues(for: kind)
        return customCategoriesProvider()
            .filter { $0.kind == kind }
            .compactMap {
                let raw = Self.customRawValue(from: $0.categoryID)
                guard includeHidden || !hiddenRaws.contains(raw) else { return nil }
                return CashflowCategoryOption(
                    rawValue: raw,
                    displayName: $0.name,
                    icon: $0.icon,
                    isCustom: true
                )
            }
    }

    // MARK: - Custom Category Visibility

    @discardableResult
    func setCustomCategoryHidden(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        isHidden: Bool
    ) -> Bool {
        customCategoryVisibilityPrefs.setHidden(isHidden, categoryRaw: categoryRaw, kind: kind)
        onCategoriesChanged()
        return true
    }

    private func fallbackCategoryRaw(for kind: CashflowCategoryKind) -> String {
        switch kind {
        case .income: return IncomeCategory.other.rawValue
        case .expense: return ExpenseCategory.other.rawValue
        }
    }

    private func isProtectedFallbackCategory(rawValue: String, kind: CashflowCategoryKind) -> Bool {
        canonicalSystemCategoryRaw(for: rawValue, kind: kind) == fallbackCategoryRaw(for: kind)
    }

    private func systemCategoryOverride(for raw: String, kind: CashflowCategoryKind) -> CashflowSystemCategoryOverride? {
        let resolvedRaw = canonicalSystemCategoryRaw(for: raw, kind: kind)
        return systemCategoryOverridesProvider().first {
            $0.kind == kind && $0.categoryRaw == resolvedRaw
        }
    }

    func baseSystemCategoryOption(for raw: String, kind: CashflowCategoryKind) -> CashflowCategoryOption? {
        switch kind {
        case .income:
            let resolvedRaw = IncomeCategory.canonicalRawValue(raw)
            guard let category = IncomeCategory(rawValue: resolvedRaw) else { return nil }
            return CashflowCategoryOption(
                rawValue: resolvedRaw,
                displayName: category.displayName,
                icon: category.icon,
                isCustom: false
            )
        case .expense:
            let resolvedRaw = ExpenseCategory.canonicalRawValue(raw)
            guard let category = ExpenseCategory(rawValue: resolvedRaw) else { return nil }
            return CashflowCategoryOption(
                rawValue: resolvedRaw,
                displayName: category.displayName,
                icon: category.icon,
                isCustom: false
            )
        }
    }

    func canonicalSystemCategoryRaw(for raw: String, kind: CashflowCategoryKind) -> String {
        switch kind {
        case .income:
            return IncomeCategory.canonicalRawValue(raw)
        case .expense:
            return ExpenseCategory.canonicalRawValue(raw)
        }
    }

    private func defaultCategoryOption(for kind: CashflowCategoryKind) -> CashflowCategoryOption {
        let fallbackRaw = fallbackCategoryRaw(for: kind)
        return systemCategoryOption(for: fallbackRaw, kind: kind, includeHidden: true) ?? CashflowCategoryOption(
            rawValue: fallbackRaw,
            displayName: "Other",
            icon: "ellipsis.circle.fill",
            isCustom: false
        )
    }

    private func resolvedSystemCategoryOverrideName(
        _ override: CashflowSystemCategoryOverride,
        base: CashflowCategoryOption,
        kind: CashflowCategoryKind
    ) -> String {
        if isDefaultSystemOverride(override, base: base, kind: kind) {
            return base.displayName
        }
        return override.name
    }

    private func isDefaultSystemOverride(
        _ override: CashflowSystemCategoryOverride,
        base: CashflowCategoryOption,
        kind: CashflowCategoryKind
    ) -> Bool {
        localizedSystemCategoryNames(for: base.rawValue, kind: kind).contains(override.normalizedName)
    }

    private func localizedSystemCategoryNames(for raw: String, kind: CashflowCategoryKind) -> Set<String> {
        switch kind {
        case .income:
            let resolvedRaw = IncomeCategory.canonicalRawValue(raw)
            guard let category = IncomeCategory(rawValue: resolvedRaw) else { return [] }
            return [
                category.localizedDisplayName(locale: Locale(identifier: "ru_RU")),
                category.localizedDisplayName(locale: Locale(identifier: "en_US"))
            ]
            .map(CashflowCustomCategory.normalize)
            .reduce(into: Set<String>()) { result, item in
                result.insert(item)
            }
        case .expense:
            guard let metadata = ExpenseCategoryCatalog.metadata(forRawValue: raw) else { return [] }
            let names = [
                metadata.displayNameRU,
                metadata.displayNameEN
            ]
            + legacyExpenseSystemCategoryNames(for: raw)
            return names
            .map(CashflowCustomCategory.normalize)
            .reduce(into: Set<String>()) { result, item in
                result.insert(item)
            }
        }
    }

    private func legacyExpenseSystemCategoryNames(for raw: String) -> [String] {
        switch ExpenseCategory.canonicalRawValue(raw) {
        case ExpenseCategory.groceries.rawValue:
            return ["Супермаркеты", "Supermarkets"]
        case ExpenseCategory.carService.rawValue:
            return ["Сервис", "Service"]
        case ExpenseCategory.utilities.rawValue:
            return ["ЖКХ и коммунальные", "Utilities & Bills"]
        case ExpenseCategory.housing.rawValue:
            return ["Счета", "Bills"]
        case ExpenseCategory.subscriptions.rawValue:
            return ["Сервисы", "Digital", "Digital services"]
        default:
            return []
        }
    }

    private func setSystemCategoryOverride(
        kind: CashflowCategoryKind,
        categoryRaw: String,
        name: String,
        icon: String,
        isHidden: Bool,
        nowDate: Date
    ) {
        let normalizedName = CashflowCustomCategory.normalize(name)
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(icon)

        if let existing = systemCategoryOverride(for: categoryRaw, kind: kind) {
            existing.name = name
            existing.normalizedName = normalizedName
            existing.icon = normalizedIcon
            existing.isHidden = isHidden
            existing.updatedAt = nowDate
            return
        }

        let newOverride = CashflowSystemCategoryOverride(
            kind: kind,
            categoryRaw: categoryRaw,
            name: name,
            icon: normalizedIcon,
            isHidden: isHidden
        )
        newOverride.updatedAt = nowDate
        modelContext.insert(newOverride)
    }

    private func removeSystemCategoryOverride(kind: CashflowCategoryKind, categoryRaw: String) {
        guard let existing = systemCategoryOverride(for: categoryRaw, kind: kind) else {
            return
        }
        modelContext.delete(existing)
    }

    // MARK: - Private: System Rename

    @discardableResult
    private func renameSystemCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        newName: String,
        newIcon: String? = nil
    ) -> Bool {
        guard let base = baseSystemCategoryOption(for: rawValue, kind: kind) else {
            return false
        }

        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalizedIcon = CashflowCustomCategory.normalizeIcon(newIcon ?? base.icon)
        let nowDate = Date()

        if let duplicateSystem = systemCategoryOptions(for: kind, includeHidden: true).first(where: {
            $0.rawValue != rawValue && $0.displayName.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            migrateTransactions(
                fromRaw: rawValue,
                toRaw: duplicateSystem.rawValue,
                kind: kind,
                nowDate: nowDate
            )
            setSystemCategoryOverride(
                kind: kind,
                categoryRaw: rawValue,
                name: base.displayName,
                icon: base.icon,
                isHidden: true,
                nowDate: nowDate
            )
            return saveCategoriesAndTransactions()
        }

        let isResetToBase = trimmed.caseInsensitiveCompare(base.displayName) == .orderedSame
            && normalizedIcon == base.icon

        if isResetToBase {
            removeSystemCategoryOverride(kind: kind, categoryRaw: rawValue)
        } else {
            setSystemCategoryOverride(
                kind: kind,
                categoryRaw: rawValue,
                name: trimmed,
                icon: normalizedIcon,
                isHidden: false,
                nowDate: nowDate
            )
        }

        return saveCategoriesAndTransactions()
    }

    // MARK: - Private: System Delete

    @discardableResult
    private func deleteSystemCategory(
        rawValue: String,
        kind: CashflowCategoryKind,
        targetRawValue: String? = nil
    ) -> CashflowCategoryMutationUndoAction? {
        guard canDeleteCategory(rawValue: rawValue, kind: kind) else {
            return nil
        }

        guard let base = baseSystemCategoryOption(for: rawValue, kind: kind) else {
            return nil
        }

        guard let target = validatedDeleteTargetOption(
            sourceRaw: rawValue,
            kind: kind,
            targetRawValue: targetRawValue
        ) else {
            return nil
        }
        let undoAction = makeCategoryMutationUndoAction(
            sourceRaw: rawValue,
            kind: kind,
            target: target,
            sourceCategory: nil,
            systemOverride: systemCategoryOverride(for: rawValue, kind: kind),
            isArchive: true
        )
        let nowDate = Date()
        migrateTransactions(fromRaw: rawValue, toRaw: target.rawValue, kind: kind, nowDate: nowDate)
        migrateBudgetCategoryLimits(fromRaw: rawValue, toRaw: target.rawValue, kind: kind, nowDate: nowDate)
        categoryPinPrefs.remap(categoryRaw: rawValue, to: target.rawValue, kind: kind)
        if kind == .expense {
            bulkExpenseMerchantPrefs.remapCategory(from: rawValue, to: target.rawValue)
        }
        setSystemCategoryOverride(
            kind: kind,
            categoryRaw: rawValue,
            name: base.displayName,
            icon: base.icon,
            isHidden: true,
            nowDate: nowDate
        )

        return saveCategoriesAndTransactions() ? undoAction : nil
    }

    // MARK: - Private: Migration

    private func migrateTransactions(
        fromRaw sourceRaw: String,
        toRaw targetRaw: String,
        kind: CashflowCategoryKind,
        nowDate: Date
    ) {
        let descriptor = FetchDescriptor<CashflowTransaction>()
        let linked = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            switch kind {
            case .income: return $0.incomeCategoryRaw == sourceRaw
            case .expense: return $0.expenseCategoryRaw == sourceRaw
            }
        }

        for transaction in linked {
            switch kind {
            case .income:
                transaction.incomeCategoryRaw = targetRaw
            case .expense:
                transaction.expenseCategoryRaw = targetRaw
            }
            transaction.updatedAt = nowDate
        }
    }

    private func migrateBudgetCategoryLimits(
        fromRaw sourceRaw: String,
        toRaw targetRaw: String,
        kind: CashflowCategoryKind,
        nowDate: Date
    ) {
        guard sourceRaw != targetRaw else { return }

        let sourceLimits = linkedBudgetCategoryLimits(for: sourceRaw, kind: kind)
        guard !sourceLimits.isEmpty else { return }

        let descriptor = FetchDescriptor<BudgetCategoryLimit>()
        let allLimits = (try? modelContext.fetch(descriptor)) ?? []

        for sourceLimit in sourceLimits {
            if let targetLimit = allLimits.first(where: {
                $0.persistentModelID != sourceLimit.persistentModelID
                    && $0.budgetID == sourceLimit.budgetID
                    && $0.categoryKind == kind
                    && $0.categoryRawValue == targetRaw
            }) {
                targetLimit.limitAmount += sourceLimit.limitAmount
                targetLimit.updatedAt = nowDate
                modelContext.delete(sourceLimit)
            } else {
                sourceLimit.categoryRawValue = targetRaw
                sourceLimit.updatedAt = nowDate
            }
        }
    }

    // MARK: - Private: Undo Helpers

    private func makeCategoryMutationUndoAction(
        sourceRaw: String,
        kind: CashflowCategoryKind,
        target: CashflowCategoryOption,
        sourceCategory: CashflowCustomCategory?,
        systemOverride: CashflowSystemCategoryOverride?,
        isArchive: Bool
    ) -> CashflowCategoryMutationUndoAction {
        let transactionSnapshots = linkedTransactions(for: sourceRaw, kind: kind).map {
            CashflowTransactionCategoryUndoSnapshot(
                transaction: $0,
                originalRawValue: sourceRaw
            )
        }
        let budgetLimitSnapshots = makeBudgetLimitUndoSnapshots(
            sourceRaw: sourceRaw,
            targetRaw: target.rawValue,
            kind: kind
        )

        return CashflowCategoryMutationUndoAction(
            kind: kind,
            sourceOption: categoryOption(for: sourceRaw, kind: kind),
            targetOption: target,
            isArchive: isArchive,
            customCategorySnapshot: sourceCategory.map(makeCustomCategorySnapshot),
            systemOverrideSnapshot: systemOverride.map(makeSystemOverrideSnapshot),
            transactionSnapshots: transactionSnapshots,
            budgetLimitSnapshots: budgetLimitSnapshots,
            pinnedRawValuesBefore: categoryPinPrefs.pinnedRawValues(for: kind),
            merchantMappingsBefore: kind == .expense ? bulkExpenseMerchantPrefs.mappingsSnapshot() : nil
        )
    }

    private func makeBudgetLimitUndoSnapshots(
        sourceRaw: String,
        targetRaw: String,
        kind: CashflowCategoryKind
    ) -> [CashflowBudgetLimitUndoSnapshot] {
        let sourceLimits = linkedBudgetCategoryLimits(for: sourceRaw, kind: kind)
        guard !sourceLimits.isEmpty else { return [] }

        let descriptor = FetchDescriptor<BudgetCategoryLimit>()
        let allLimits = (try? modelContext.fetch(descriptor)) ?? []

        return sourceLimits.map { sourceLimit in
            if let targetLimit = allLimits.first(where: {
                $0.persistentModelID != sourceLimit.persistentModelID
                    && $0.budgetID == sourceLimit.budgetID
                    && $0.categoryKind == kind
                    && $0.categoryRawValue == targetRaw
            }) {
                return .merged(
                    source: makeBudgetLimitRecordSnapshot(sourceLimit),
                    target: targetLimit,
                    targetOriginalAmount: targetLimit.limitAmount
                )
            }

            return .updated(
                limit: sourceLimit,
                originalRawValue: sourceLimit.categoryRawValue,
                originalAmount: sourceLimit.limitAmount
            )
        }
    }

    private func restoreBudgetLimitSnapshots(_ snapshots: [CashflowBudgetLimitUndoSnapshot]) {
        for snapshot in snapshots {
            switch snapshot {
            case .updated(let limit, let originalRawValue, let originalAmount):
                limit.categoryRawValue = originalRawValue
                limit.limitAmount = originalAmount
                limit.updatedAt = now()

            case .merged(let source, let target, let targetOriginalAmount):
                target.limitAmount = targetOriginalAmount
                target.updatedAt = now()
                restoreBudgetLimit(from: source)
            }
        }
    }

    private func restoreBudgetLimit(from snapshot: CashflowBudgetLimitRecordSnapshot) {
        let limit = BudgetCategoryLimit(
            budgetID: snapshot.budgetID,
            categoryKind: snapshot.categoryKind,
            categoryRawValue: snapshot.categoryRawValue,
            limitAmount: snapshot.limitAmount
        )
        limit.categoryLimitID = snapshot.categoryLimitID
        limit.createdAt = snapshot.createdAt
        limit.updatedAt = snapshot.updatedAt
        modelContext.insert(limit)
    }

    private func restoreCustomCategory(from snapshot: CashflowCustomCategorySnapshot) {
        let existing = customCategoriesProvider().first {
            $0.categoryID == snapshot.categoryID && $0.kind == snapshot.kind
        } ?? ((try? modelContext.fetch(FetchDescriptor<CashflowCustomCategory>())) ?? []).first {
            $0.categoryID == snapshot.categoryID && $0.kind == snapshot.kind
        }

        if let existing {
            existing.name = snapshot.name
            existing.normalizedName = snapshot.normalizedName
            existing.icon = snapshot.icon
            existing.createdAt = snapshot.createdAt
            existing.updatedAt = snapshot.updatedAt
            return
        }

        let category = CashflowCustomCategory(
            kind: snapshot.kind,
            name: snapshot.name,
            icon: snapshot.icon
        )
        category.categoryID = snapshot.categoryID
        category.normalizedName = snapshot.normalizedName
        category.createdAt = snapshot.createdAt
        category.updatedAt = snapshot.updatedAt
        modelContext.insert(category)
    }

    private func restoreSystemCategoryOverride(
        _ snapshot: CashflowSystemCategoryOverrideSnapshot?,
        sourceRaw: String,
        kind: CashflowCategoryKind
    ) {
        guard let snapshot else {
            removeSystemCategoryOverride(kind: kind, categoryRaw: sourceRaw)
            return
        }

        if let existing = systemCategoryOverride(for: sourceRaw, kind: kind) {
            existing.name = snapshot.name
            existing.normalizedName = snapshot.normalizedName
            existing.icon = snapshot.icon
            existing.isHidden = snapshot.isHidden
            existing.createdAt = snapshot.createdAt
            existing.updatedAt = snapshot.updatedAt
            return
        }

        let override = CashflowSystemCategoryOverride(
            kind: snapshot.kind,
            categoryRaw: snapshot.categoryRaw,
            name: snapshot.name,
            icon: snapshot.icon,
            isHidden: snapshot.isHidden
        )
        override.overrideID = snapshot.overrideID
        override.normalizedName = snapshot.normalizedName
        override.createdAt = snapshot.createdAt
        override.updatedAt = snapshot.updatedAt
        modelContext.insert(override)
    }

    private func makeCustomCategorySnapshot(_ category: CashflowCustomCategory) -> CashflowCustomCategorySnapshot {
        CashflowCustomCategorySnapshot(
            categoryID: category.categoryID,
            kind: category.kind,
            name: category.name,
            normalizedName: category.normalizedName,
            icon: category.icon,
            createdAt: category.createdAt,
            updatedAt: category.updatedAt
        )
    }

    private func makeSystemOverrideSnapshot(_ override: CashflowSystemCategoryOverride) -> CashflowSystemCategoryOverrideSnapshot {
        CashflowSystemCategoryOverrideSnapshot(
            overrideID: override.overrideID,
            kind: override.kind,
            categoryRaw: override.categoryRaw,
            name: override.name,
            normalizedName: override.normalizedName,
            icon: override.icon,
            isHidden: override.isHidden,
            createdAt: override.createdAt,
            updatedAt: override.updatedAt
        )
    }

    private func makeBudgetLimitRecordSnapshot(_ limit: BudgetCategoryLimit) -> CashflowBudgetLimitRecordSnapshot {
        CashflowBudgetLimitRecordSnapshot(
            categoryLimitID: limit.categoryLimitID,
            budgetID: limit.budgetID,
            categoryKind: limit.categoryKind,
            categoryRawValue: limit.categoryRawValue,
            limitAmount: limit.limitAmount,
            createdAt: limit.createdAt,
            updatedAt: limit.updatedAt
        )
    }

    // MARK: - Private: DB Queries

    private func linkedTransactions(for rawValue: String, kind: CashflowCategoryKind) -> [CashflowTransaction] {
        let descriptor = FetchDescriptor<CashflowTransaction>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            switch kind {
            case .income:
                return $0.incomeCategoryRaw == rawValue
            case .expense:
                return $0.expenseCategoryRaw == rawValue
            }
        }
    }

    private func linkedBudgetCategoryLimits(for rawValue: String, kind: CashflowCategoryKind) -> [BudgetCategoryLimit] {
        let descriptor = FetchDescriptor<BudgetCategoryLimit>()
        return ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.categoryKind == kind && $0.categoryRawValue == rawValue
        }
    }

    private func validatedDeleteTargetOption(
        sourceRaw: String,
        kind: CashflowCategoryKind,
        targetRawValue: String?
    ) -> CashflowCategoryOption? {
        let resolvedTargetRaw = canonicalSystemCategoryRaw(
            for: targetRawValue ?? fallbackCategoryRaw(for: kind),
            kind: kind
        )
        guard resolvedTargetRaw != canonicalSystemCategoryRaw(for: sourceRaw, kind: kind) else {
            return nil
        }

        let options = categoryOptions(for: kind, includeHiddenSystem: true)
        guard options.contains(where: { $0.rawValue == resolvedTargetRaw }) else {
            return nil
        }
        return categoryOption(for: resolvedTargetRaw, kind: kind)
    }

    // MARK: - Private: Save

    @discardableResult
    private func saveCategoriesAndTransactions() -> Bool {
        do {
            try modelContext.save()
            onCategoriesChanged()
            return true
        } catch {
            AppLogger.log(.error, category: "Cashflow", "Failed to save category changes: \(error.localizedDescription)")
            return false
        }
    }
}
