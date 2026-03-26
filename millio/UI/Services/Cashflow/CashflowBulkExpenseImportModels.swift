//
//  CashflowBulkExpenseImportModels.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

import Foundation

enum CashflowBulkExpenseImportMode: String, CaseIterable, Identifiable {
    case manual
    case screenshot

    var id: String { rawValue }

    var requiresPremiumAccess: Bool {
        self == .screenshot
    }

    var title: String {
        switch self {
        case .manual:
            return String(
                localized: "cashflow.bulk_expense.mode.manual",
                defaultValue: "Manual",
                comment: "Mode title for manual bulk expense import"
            )
        case .screenshot:
            return String(
                localized: "cashflow.bulk_expense.mode.screenshot",
                defaultValue: "Screenshot",
                comment: "Mode title for screenshot bulk expense import"
            )
        }
    }

    func isUnlocked(canImportScreenshots: Bool) -> Bool {
        switch self {
        case .manual:
            return true
        case .screenshot:
            return canImportScreenshots
        }
    }
}

enum CashflowBulkExpenseImportTransactionSource: String {
    case monthlyCategoryRollup = "monthly_category_rollup"
}

enum CashflowBulkExpenseImportMatchConfidence: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: CashflowBulkExpenseImportMatchConfidence, rhs: CashflowBulkExpenseImportMatchConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .low:
            return String(
                localized: "cashflow.bulk_expense.confidence.low",
                defaultValue: "Check",
                comment: "Low confidence match badge"
            )
        case .medium:
            return String(
                localized: "cashflow.bulk_expense.confidence.medium",
                defaultValue: "Good",
                comment: "Medium confidence match badge"
            )
        case .high:
            return String(
                localized: "cashflow.bulk_expense.confidence.high",
                defaultValue: "Auto",
                comment: "High confidence match badge"
            )
        }
    }
}

struct CashflowBulkExpenseParsedRow: Equatable {
    let rawLine: String
    let title: String
    let amount: Double
    let sourceOrderIndex: Int
}

struct CashflowBulkExpenseCategoryResolution: Equatable {
    let option: CashflowCategoryOption
    let confidence: CashflowBulkExpenseImportMatchConfidence

    var requiresManualReview: Bool {
        confidence == .low || option.rawValue == ExpenseCategory.other.rawValue
    }
}

struct CashflowBulkExpenseRowDraft: Identifiable, Equatable {
    let id: UUID
    var rawLine: String
    var titleText: String
    var amountText: String
    var selectedCategoryRaw: String
    var suggestedCategoryRaws: [String]
    var noteText: String
    var sourceOrderIndex: Int
    var confidence: CashflowBulkExpenseImportMatchConfidence
    var usesSuggestedCategory: Bool

    init(
        id: UUID = UUID(),
        rawLine: String,
        titleText: String,
        amountText: String,
        selectedCategoryRaw: String = ExpenseCategory.other.rawValue,
        suggestedCategoryRaws: [String] = [],
        noteText: String = "",
        sourceOrderIndex: Int,
        confidence: CashflowBulkExpenseImportMatchConfidence = .low,
        usesSuggestedCategory: Bool = true
    ) {
        self.id = id
        self.rawLine = rawLine
        self.titleText = titleText
        self.amountText = amountText
        self.selectedCategoryRaw = selectedCategoryRaw
        self.suggestedCategoryRaws = suggestedCategoryRaws
        self.noteText = noteText
        self.sourceOrderIndex = sourceOrderIndex
        self.confidence = confidence
        self.usesSuggestedCategory = usesSuggestedCategory
    }

    var normalizedTitle: String {
        titleText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedNote: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var amount: Double? {
        Self.parseAmount(amountText)
    }

    var isAddable: Bool {
        guard let amount, amount > 0 else { return false }
        return !selectedCategoryRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var requiresAttention: Bool {
        guard isAddable else { return true }
        guard usesSuggestedCategory else { return false }
        return confidence == .low || selectedCategoryRaw == ExpenseCategory.other.rawValue
    }

    var normalizedExpenseNote: String? {
        let title = normalizedTitle
        let note = normalizedNote
        guard !note.isEmpty else { return title.isEmpty ? nil : title }
        if note.caseInsensitiveCompare(title) == .orderedSame {
            return title.isEmpty ? nil : title
        }
        if title.isEmpty {
            return note
        }
        return "\(title) • \(note)"
    }

    static func parseAmount(_ rawValue: String) -> Double? {
        let trimmed = rawValue
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let negative = trimmed.contains("-")
        let allowed = trimmed.filter {
            $0.isNumber || $0 == "," || $0 == "." || $0 == " "
        }
        let compact = allowed.replacingOccurrences(of: " ", with: "")
        guard compact.contains(where: \.isNumber) else { return nil }

        let separators = compact.enumerated().compactMap { index, character -> Int? in
            (character == "," || character == ".") ? index : nil
        }

        let normalized: String
        if let lastSeparator = separators.last {
            let fractionalCount = compact.distance(from: compact.index(compact.startIndex, offsetBy: lastSeparator), to: compact.endIndex) - 1
            if fractionalCount > 0 && fractionalCount <= 2 {
                let integerPart = compact[..<compact.index(compact.startIndex, offsetBy: lastSeparator)]
                    .filter(\.isNumber)
                let fractionalPart = compact[compact.index(compact.startIndex, offsetBy: lastSeparator)...]
                    .dropFirst()
                    .filter(\.isNumber)
                normalized = "\(integerPart).\(fractionalPart)"
            } else {
                normalized = String(compact.filter(\.isNumber))
            }
        } else {
            normalized = String(compact.filter(\.isNumber))
        }

        guard let amount = Double(normalized), amount > 0 else { return nil }
        _ = negative
        return amount
    }

    static func formatAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = value.rounded() == value ? 0 : 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

struct CashflowBulkExpensePersistEntry: Equatable {
    let amount: Double
    let expenseCategoryRaw: String
    let note: String?
    let sourceOrderIndex: Int
}

struct CashflowBulkExpenseCategoryDraft: Identifiable, Equatable {
    let id: String
    let category: CashflowCategoryOption
    var amountText: String
    var noteText: String
    var sourceOrderIndex: Int

    init(
        category: CashflowCategoryOption,
        amountText: String = "",
        noteText: String = "",
        sourceOrderIndex: Int
    ) {
        self.id = category.rawValue
        self.category = category
        self.amountText = amountText
        self.noteText = noteText
        self.sourceOrderIndex = sourceOrderIndex
    }

    var amount: Double? {
        CashflowBulkExpenseRowDraft.parseAmount(amountText)
    }

    var hasValue: Bool {
        guard let amount else { return false }
        return amount > 0.0000001
    }

    var normalizedNote: String? {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct CashflowBulkExpenseCategoryBreakdown: Equatable {
    let baselineAmount: Double
    let importedAmount: Double

    var displayedTotal: Double {
        baselineAmount + importedAmount
    }

    static func make(
        displayedAmount: Double?,
        baselineAmount: Double
    ) -> CashflowBulkExpenseCategoryBreakdown {
        let normalizedBaseline = max(0, baselineAmount)
        let normalizedDisplayed = max(0, displayedAmount ?? 0)
        let importedAmount = max(0, normalizedDisplayed - normalizedBaseline)
        return CashflowBulkExpenseCategoryBreakdown(
            baselineAmount: normalizedBaseline,
            importedAmount: importedAmount
        )
    }
}

struct CashflowBulkExpensePreviewApplyResult: Equatable {
    let categoryDrafts: [CashflowBulkExpenseCategoryDraft]
    let importedCategoryRaws: Set<String>
    let appliedRows: [CashflowBulkExpenseRowDraft]
    let remainingRows: [CashflowBulkExpenseRowDraft]
}

enum CashflowBulkExpenseScreenshotReviewPolicy {
    static func makePreviewRows(
        parsedRows: [CashflowBulkExpenseParsedRow],
        availableOptions: [CashflowCategoryOption],
        resolver: CashflowBulkExpenseImportCategoryResolver = CashflowBulkExpenseImportCategoryResolver(),
        preferredRawValueForTitle: (String) -> String?
    ) -> [CashflowBulkExpenseRowDraft] {
        parsedRows
            .sorted { $0.sourceOrderIndex < $1.sourceOrderIndex }
            .enumerated()
            .map { index, row in
                refreshPreviewRow(
                    CashflowBulkExpenseRowDraft(
                        rawLine: row.rawLine,
                        titleText: row.title,
                        amountText: CashflowBulkExpenseRowDraft.formatAmount(row.amount),
                        sourceOrderIndex: index
                    ),
                    availableOptions: availableOptions,
                    resolver: resolver,
                    preferredRawValue: preferredRawValueForTitle(row.title)
                )
            }
    }

    static func refreshPreviewRow(
        _ row: CashflowBulkExpenseRowDraft,
        availableOptions: [CashflowCategoryOption],
        resolver: CashflowBulkExpenseImportCategoryResolver = CashflowBulkExpenseImportCategoryResolver(),
        preferredRawValue: String?
    ) -> CashflowBulkExpenseRowDraft {
        let resolution = resolver.resolve(
            title: row.normalizedTitle,
            availableOptions: availableOptions,
            preferredRawValue: preferredRawValue
        )
        let suggestedRaws = uniqueRawValues(
            from: [resolution.option.rawValue] +
                resolver.suggestedOptions(
                    title: row.normalizedTitle,
                    availableOptions: availableOptions,
                    preferredRawValue: preferredRawValue
                ).map(\.rawValue)
        )

        var updated = row
        updated.confidence = resolution.confidence
        updated.suggestedCategoryRaws = suggestedRaws

        let currentSelectionExists = availableOptions.contains { $0.rawValue == row.selectedCategoryRaw }
        if row.usesSuggestedCategory || !currentSelectionExists {
            updated.selectedCategoryRaw = resolution.option.rawValue
            updated.usesSuggestedCategory = true
        } else if updated.suggestedCategoryRaws.contains(row.selectedCategoryRaw) == false {
            updated.suggestedCategoryRaws = uniqueRawValues(from: [row.selectedCategoryRaw] + updated.suggestedCategoryRaws)
        }

        return updated
    }

    static func applyPreviewRows(
        _ rows: [CashflowBulkExpenseRowDraft],
        to categoryDrafts: [CashflowBulkExpenseCategoryDraft]
    ) -> CashflowBulkExpensePreviewApplyResult {
        var updatedDrafts = categoryDrafts
        var importedCategoryRaws: Set<String> = []
        var appliedRows: [CashflowBulkExpenseRowDraft] = []
        var remainingRows: [CashflowBulkExpenseRowDraft] = []

        for row in rows.sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex }) {
            guard let amount = row.amount, amount > 0.0000001, row.requiresAttention == false else {
                remainingRows.append(row)
                continue
            }
            guard let categoryIndex = updatedDrafts.firstIndex(where: { $0.category.rawValue == row.selectedCategoryRaw }) else {
                remainingRows.append(row)
                continue
            }

            let existingAmount = updatedDrafts[categoryIndex].amount ?? 0
            updatedDrafts[categoryIndex].amountText = CashflowBulkExpenseRowDraft.formatAmount(existingAmount + amount)
            importedCategoryRaws.insert(row.selectedCategoryRaw)
            appliedRows.append(row)
        }

        return CashflowBulkExpensePreviewApplyResult(
            categoryDrafts: updatedDrafts,
            importedCategoryRaws: importedCategoryRaws,
            appliedRows: appliedRows,
            remainingRows: remainingRows
        )
    }

    private static func uniqueRawValues(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { value in
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
            return seen.insert(value).inserted
        }
    }
}

struct CashflowBulkExpenseCategorySortPolicy {
    static func orderedDraftIndices(
        drafts: [CashflowBulkExpenseCategoryDraft],
        searchText: String,
        importedCategoryRaws: Set<String>
    ) -> [Int] {
        let trimmedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        return drafts.indices
            .filter { index in
                guard !trimmedQuery.isEmpty else { return true }
                return drafts[index].category.displayName.localizedCaseInsensitiveContains(trimmedQuery)
            }
            .sorted { lhs, rhs in
                let left = drafts[lhs]
                let right = drafts[rhs]
                let leftImported = importedCategoryRaws.contains(left.category.rawValue) && left.hasValue
                let rightImported = importedCategoryRaws.contains(right.category.rawValue) && right.hasValue

                if leftImported != rightImported {
                    return leftImported && !rightImported
                }

                if leftImported && rightImported {
                    let leftAmount = left.amount ?? 0
                    let rightAmount = right.amount ?? 0
                    if abs(leftAmount - rightAmount) > 0.0000001 {
                        return leftAmount > rightAmount
                    }
                }

                let leftHasValue = left.hasValue
                let rightHasValue = right.hasValue
                if leftHasValue != rightHasValue {
                    return leftHasValue && !rightHasValue
                }

                if left.sourceOrderIndex != right.sourceOrderIndex {
                    return left.sourceOrderIndex < right.sourceOrderIndex
                }

                return left.category.rawValue < right.category.rawValue
            }
    }

    static func isTransferCategory(_ rawValue: String) -> Bool {
        rawValue == ExpenseCategory.transfers.rawValue
    }
}

struct CashflowBulkExpenseStoredCategoryEntry: Equatable {
    let categoryRaw: String
    let amount: Double
    let note: String?
    let affectsCardBalance: Bool
}

struct CashflowBulkExpensePersistRequest: Equatable {
    let cardID: String
    let month: Date
    let shouldAffectCardBalance: Bool
    let entries: [CashflowBulkExpensePersistEntry]
}

struct CashflowBulkExpenseImportSelectionPolicy {
    static func availableCurrencies(
        cards: [Card],
        preferredCurrency: String
    ) -> [String] {
        let unique = Set(cards.map(\.currency))
        guard !unique.isEmpty else { return [preferredCurrency] }
        return unique.sorted { lhs, rhs in
            if lhs == preferredCurrency { return true }
            if rhs == preferredCurrency { return false }
            return lhs < rhs
        }
    }

    static func normalizeSelection(
        cards: [Card],
        selectedCurrency: String,
        selectedCardID: String?,
        preferredCurrency: String
    ) -> (currency: String, cardID: String?) {
        guard !cards.isEmpty else {
            return (selectedCurrency.isEmpty ? preferredCurrency : selectedCurrency, nil)
        }

        let currencies = availableCurrencies(cards: cards, preferredCurrency: preferredCurrency)
        let effectiveCurrency = currencies.contains(selectedCurrency)
            ? selectedCurrency
            : (currencies.first ?? preferredCurrency)
        let compatibleCards = cards.filter { $0.currency == effectiveCurrency }
        let selectedCard = compatibleCards.first { $0.cardUniqueID == selectedCardID }
        let effectiveCardID = selectedCard?.cardUniqueID
            ?? compatibleCards.first(where: \.isFavorite)?.cardUniqueID
            ?? compatibleCards.first?.cardUniqueID

        return (effectiveCurrency, effectiveCardID)
    }
}

enum CashflowBulkExpenseImportError: LocalizedError {
    case invalidImage
    case noTextFound
    case noExpenseRowsFound
    case noRowsToSave
    case cardNotFound
    case insufficientFunds(required: Double, available: Double, currency: String)

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return String(
                localized: "cashflow.bulk_expense.error.invalid_image",
                defaultValue: "The image could not be read.",
                comment: "Bulk expense screenshot import invalid image error"
            )
        case .noTextFound:
            return String(
                localized: "cashflow.bulk_expense.error.no_text",
                defaultValue: "No text was found on the screenshot.",
                comment: "Bulk expense screenshot import no text error"
            )
        case .noExpenseRowsFound:
            return String(
                localized: "cashflow.bulk_expense.error.no_rows",
                defaultValue: "No expense rows were recognized.",
                comment: "Bulk expense screenshot import no rows error"
            )
        case .noRowsToSave:
            return String(
                localized: "cashflow.bulk_expense.error.no_rows_to_save",
                defaultValue: "Add at least one valid expense row.",
                comment: "Bulk expense import save error without rows"
            )
        case .cardNotFound:
            return String(
                localized: "cashflow.bulk_expense.error.card_not_found",
                defaultValue: "Select an active card before saving.",
                comment: "Bulk expense import save error without card"
            )
        case .insufficientFunds(let required, let available, let currency):
            return String(
                localized: "cashflow.bulk_expense.error.insufficient_funds",
                defaultValue: "Not enough funds: \(CashflowBulkExpenseRowDraft.formatAmount(required)) \(currency) needed, \(CashflowBulkExpenseRowDraft.formatAmount(available)) \(currency) available.",
                comment: "Bulk expense import insufficient funds error"
            )
        }
    }
}
