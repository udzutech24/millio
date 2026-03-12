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
}

struct CashflowBulkExpenseRowDraft: Identifiable, Equatable {
    let id: UUID
    var rawLine: String
    var titleText: String
    var amountText: String
    var selectedCategoryRaw: String
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
