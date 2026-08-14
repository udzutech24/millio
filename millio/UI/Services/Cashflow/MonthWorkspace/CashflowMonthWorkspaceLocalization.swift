import Foundation

enum CashflowMonthWorkspaceLocalization {
    static var title: String { L("cashflow.month_workspace.title") }
    static var year: String { L("cashflow.month_workspace.year") }
    static var chooseMonth: String { L("cashflow.month_workspace.choose_month") }
    static var chooseMonthHint: String { L("cashflow.month_workspace.choose_month_hint") }
    static var monthActions: String { L("cashflow.month_workspace.month_actions") }
    static func monthDestinationHint(_ month: String) -> String {
        String(format: L("cashflow.month_workspace.month_destination_hint"), month)
    }
    static var wholeMonthHint: String { L("cashflow.month_workspace.whole_month_hint") }
    static var previousMonth: String { L("cashflow.month_workspace.previous_month") }
    static var nextMonth: String { L("cashflow.month_workspace.next_month") }
    static var done: String { L("cashflow.month_workspace.done") }
    static var expense: String { L("cashflow.month_workspace.expense") }
    static var income: String { L("cashflow.month_workspace.income") }
    static var transfer: String { L("cashflow.month_workspace.transfer") }
    static var add: String { L("cashflow.month_workspace.add") }
    static var noTransactions: String { L("cashflow.month_workspace.no_transactions") }
    static var emptyHint: String { L("cashflow.month_workspace.empty_hint") }
    static var importData: String { L("cashflow.month_workspace.import_data") }
    static var importMonth: String { L("cashflow.month_workspace.import_month") }
    static var importMonthHint: String { L("cashflow.month_workspace.import_month_hint") }
    static var chooseAnotherMonth: String { L("cashflow.month_workspace.choose_another_month") }
    static func switchToMonth(_ month: String) -> String {
        String(format: L("cashflow.month_workspace.switch_to_month"), month)
    }
    static var history: String { L("cashflow.month_workspace.history") }
    static var analytics: String { L("cashflow.month_workspace.analytics") }
    static var expenseBudget: String { L("cashflow.month_workspace.expense_budget") }
    static var incomeBudget: String { L("cashflow.month_workspace.income_budget") }
    static var manualBulk: String { L("cashflow.month_workspace.manual_bulk") }
    static var statement: String { L("cashflow.month_workspace.statement") }
    static var privacy: String { L("cashflow.month_workspace.privacy") }
    static var unavailable: String { L("cashflow.month_workspace.unavailable") }
    static var unsupported: String { L("cashflow.month_workspace.unsupported") }
    static var reconciliationFailed: String { L("cashflow.month_workspace.reconciliation_failed") }
    static var monthMismatch: String { L("cashflow.month_workspace.month_mismatch") }
    static var account: String { L("cashflow.month_workspace.account") }
    static var selectAccount: String { L("cashflow.month_workspace.select_account") }
    static var linkToAccount: String { L("cashflow.month_workspace.link_to_account") }
    static var accountBalanceUnchanged: String { L("cashflow.month_workspace.account_balance_unchanged") }
    static var review: String { L("cashflow.month_workspace.review") }
    static var category: String { L("cashflow.month_workspace.category") }
    static var applySelected: String { L("cashflow.month_workspace.apply_selected") }
    static var confirmImport: String { L("cashflow.month_workspace.confirm_import") }
    static var confirmImportMessage: String { L("cashflow.month_workspace.confirm_import_message") }
    static var summary: String { L("cashflow.month_workspace.summary") }
    static var categoryBreakdown: String { L("cashflow.month_workspace.category_breakdown") }
    static func transactionCount(_ count: Int) -> String {
        L("cashflow.month_workspace.transaction_count \(count)")
    }
    static var totalRows: String { L("cashflow.month_workspace.total_rows") }
    static var includedRows: String { L("cashflow.month_workspace.included_rows") }
    static var excludedRows: String { L("cashflow.month_workspace.excluded_rows") }
    static var duplicates: String { L("cashflow.month_workspace.duplicates") }
    static var transfers: String { L("cashflow.month_workspace.transfers") }
    static var reconciliation: String { L("cashflow.month_workspace.reconciliation") }
    static var reconciliationSuccess: String { L("cashflow.month_workspace.reconciliation_success") }
    static var difference: String { L("cashflow.month_workspace.difference") }
    static var excludedDuplicate: String { L("cashflow.month_workspace.excluded_duplicate") }
    static var excludedTransfer: String { L("cashflow.month_workspace.excluded_transfer") }
    static var excludedTechnical: String { L("cashflow.month_workspace.excluded_technical") }
    static var applying: String { L("cashflow.month_workspace.applying") }
    static var retryFailure: String { L("cashflow.month_workspace.retry_failure") }
    static var applyFailure: String { L("cashflow.month_workspace.apply_failure") }
    static var open: String { L("cashflow.month_workspace.open") }
    static var closed: String { L("cashflow.month_workspace.closed") }
    static var closeMonth: String { L("cashflow.month_workspace.close_month") }
    static var reopenMonth: String { L("cashflow.month_workspace.reopen_month") }
    static var closeExplanation: String { L("cashflow.month_workspace.close_explanation") }
    static var notReady: String { L("cashflow.month_workspace.not_ready") }
    static var ready: String { L("cashflow.month_workspace.ready") }
    static var closedExplanation: String { L("cashflow.month_workspace.closed_explanation") }
    static var confirmClose: String { L("cashflow.month_workspace.confirm_close") }
    static var confirmReopen: String { L("cashflow.month_workspace.confirm_reopen") }
    static var cancel: String { L("cashflow.month_workspace.cancel") }
}
