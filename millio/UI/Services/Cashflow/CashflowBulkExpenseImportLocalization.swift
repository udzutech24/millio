//
//  CashflowBulkExpenseImportLocalization.swift
//  millio
//
//  Created by Codex on 31.03.2026.
//

import Foundation

enum CashflowBulkExpenseImportLocalization {
    static let title = string("cashflow.bulk_expense.title")
    static let helpOpen = string("cashflow.bulk_expense.help.open")
    static let save = string("cashflow.bulk_expense.save")
    static let cardTitle = string("cashflow.bulk_expense.card_title")
    static let pickCard = string("cashflow.bulk_expense.pick_card")
    static let affectBalanceCompact = string("cashflow.bulk_expense.affect_balance.compact")
    static let affectBalance = string("cashflow.bulk_expense.affect_balance")
    static let done = string("cashflow.common.done")
    static let screenshotHint = string("cashflow.bulk_expense.screenshot.hint")
    static let screenshotReviewTitle = string("cashflow.bulk_expense.review.title")
    static let screenshotReviewSubtitle = string("cashflow.bulk_expense.review.subtitle")
    static let screenshotReviewRows = string("cashflow.bulk_expense.review.rows")
    static let screenshotReviewApply = string("cashflow.bulk_expense.review.apply")
    static let rowTitlePlaceholder = string("cashflow.bulk_expense.row.title_placeholder")
    static let rowAmountPlaceholder = string("cashflow.bulk_expense.row.amount_placeholder")
    static let rowAttention = string("cashflow.bulk_expense.row.attention")
    static let useCategory = string("cashflow.bulk_expense.row.use_category")
    static let createCategory = string("cashflow.bulk_expense.category.create_action")
    static let categories = string("cashflow.bulk_expense.summary.rows")
    static let total = string("cashflow.bulk_expense.summary.total")
    static let searchCategory = string("cashflow.bulk_expense.search.placeholder")
    static let clearAmount = string("cashflow.bulk_expense.tile.clear")
    static let monthPickerTitle = string("cashflow.bulk_expense.month_picker.title")
    static let monthPickerSubtitle = string("cashflow.bulk_expense.month_picker.subtitle")
    static let helpSheetTitle = string("cashflow.bulk_expense.help.sheet_title")
    static let helpHeroBody = string("cashflow.bulk_expense.help.hero.body")
    static let cropTitle = string("cashflow.bulk_expense.help.crop.title")
    static let cropSubtitle = string("cashflow.bulk_expense.help.crop.subtitle")
    static let cropDo = string("cashflow.bulk_expense.help.crop.do")
    static let cropDoSecond = string("cashflow.bulk_expense.help.crop.do_second")
    static let cropDont = string("cashflow.bulk_expense.help.crop.dont")
    static let cropWarning = string("cashflow.bulk_expense.help.crop.warning")
    static let cropExampleTitle = string("cashflow.bulk_expense.help.crop.example_title")
    static let cropExampleHistory = string("cashflow.bulk_expense.help.crop.example.history")
    static let cropExampleMerchantGroceries = string("cashflow.bulk_expense.help.crop.example.merchant.groceries")
    static let cropExampleMerchantTaxi = string("cashflow.bulk_expense.help.crop.example.merchant.taxi")
    static let cropExampleMerchantCoffee = string("cashflow.bulk_expense.help.crop.example.merchant.coffee")
    static let cropExampleMerchantTransfer = string("cashflow.bulk_expense.help.crop.example.merchant.transfer")
    static let cropExampleBalance = string("cashflow.bulk_expense.help.crop.example.zone.balance")
    static let cropExampleCards = string("cashflow.bulk_expense.help.crop.example.zone.cards")
    static let cropExampleNav = string("cashflow.bulk_expense.help.crop.example.zone.nav")
    static let screenshotProcessing = string("cashflow.bulk_expense.screenshot.processing")
    static let screenshotPick = string("cashflow.bulk_expense.screenshot.pick")
    static let screenshotStepBody = string("cashflow.bulk_expense.help.step.screenshot.body")
    static let emptyParse = string("cashflow.bulk_expense.manual.empty_parse")

    static func toggleState(isEnabled: Bool) -> String {
        string(isEnabled ? "cashflow.bulk_expense.toggle.on" : "cashflow.bulk_expense.toggle.off")
    }

    static func suggestion(_ categoryName: String) -> String {
        formatted(
            "cashflow.bulk_expense.row.suggestion",
            defaultValue: "Suggestion: %@",
            categoryName
        )
    }

    static func categoryBreakdownLabel(baselineAmount: Double, importedAmount: Double) -> String {
        formatted(
            "cashflow.bulk_expense.category.breakdown",
            defaultValue: "Manual %@ + Import %@",
            CashflowBulkExpenseRowDraft.formatAmount(baselineAmount),
            CashflowBulkExpenseRowDraft.formatAmount(importedAmount)
        )
    }

    static func mergeReviewRequiredMessage() -> String {
        string(
            "cashflow.bulk_expense.screenshot.merge.review_required",
            fallback: "Review or remove the rows that still need attention before merging them into monthly categories."
        )
    }

    static func mergeCompletedMessage() -> String {
        string(
            "cashflow.bulk_expense.screenshot.merge.completed",
            fallback: "Reviewed rows were moved into categories. You can save the import now."
        )
    }

    static func mergePartialMessage(appliedCount: Int, remainingCount: Int) -> String {
        formatted(
            "cashflow.bulk_expense.screenshot.merge.partial",
            defaultValue: "Moved %@ rows. %@ still need review.",
            String(appliedCount),
            String(remainingCount)
        )
    }

    static func recognizedRowsMessage(_ count: Int) -> String {
        formatted(
            "cashflow.bulk_expense.screenshot.recognized",
            defaultValue: "Recognized %@ rows. Review them before moving them into categories.",
            String(count)
        )
    }

    static func balanceWarning(amount: Double, currencyCode: String) -> String {
        formatted(
            "cashflow.bulk_expense.summary.balance_warning",
            defaultValue: "This import exceeds the selected card balance by %@ %@.",
            CashflowBulkExpenseRowDraft.formatAmount(amount),
            currencyCode
        )
    }

    static func savedMessage(count: Int) -> String {
        formatted(
            "cashflow.bulk_expense.saved",
            defaultValue: "Saved %@ category totals.",
            String(count)
        )
    }

    static func monthTitle(for month: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter.string(from: month).localizedCapitalized
    }

    static func periodRangeTitle(for month: Date, calendar: Calendar = .autoupdatingCurrent) -> String {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start

        let formatter = DateFormatter()
        formatter.locale = AppLocalization.currentAppLocale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")

        return String(
            format: AppLocalization.string(
                "cashflow.period.range_format",
                locale: AppLocalization.currentAppLocale,
                fallback: "%1$@ — %2$@"
            ),
            locale: AppLocalization.currentAppLocale,
            formatter.string(from: start),
            formatter.string(from: end)
        )
    }

    private static func string(_ key: String, fallback: String? = nil) -> String {
        AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: fallback)
    }

    private static func formatted(_ key: String, defaultValue: String, _ arguments: CVarArg...) -> String {
        String(
            format: AppLocalization.string(key, locale: AppLocalization.currentAppLocale, fallback: defaultValue),
            locale: AppLocalization.currentAppLocale,
            arguments: arguments
        )
    }
}
