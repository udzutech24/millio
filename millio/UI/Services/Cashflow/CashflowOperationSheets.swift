//
//  CashflowOperationSheets.swift
//  millio
//
//  Created by Codex on 01.03.2026.
//

import SwiftUI
import UIKit

enum CashflowOperationSheetLayoutPolicy {
    static let floatingAddCategoryButtonSize: CGFloat = 64
    static let floatingAddCategoryBottomPadding: CGFloat = 20

    static func scrollContentBottomPadding() -> CGFloat {
        BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: floatingAddCategoryButtonSize,
            overlayBottomPadding: floatingAddCategoryBottomPadding
        )
    }
}

enum CashflowCategorySheetBootstrap {
    @MainActor
    static func prepare(viewModel: CashflowViewModel) {
        viewModel.handle(.loadCards)
        viewModel.handle(.loadTransactions)
    }

    /// Builds the default transaction date for category-driven creation flows.
    /// We keep the current day-of-month when possible, but always clamp the
    /// result into the month currently selected in the category sheet.
    nonisolated static func initialTransactionDate(
        forSelectedMonth selectedMonth: Date,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date {
        let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: selectedMonth)
        ) ?? selectedMonth
        let referenceComponents = calendar.dateComponents(
            [.hour, .minute, .second, .nanosecond],
            from: referenceDate
        )
        let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let clampedDay = min(max(calendar.component(.day, from: referenceDate), 1), maxDay)

        var components = calendar.dateComponents([.year, .month], from: monthStart)
        components.day = clampedDay
        components.hour = referenceComponents.hour
        components.minute = referenceComponents.minute
        components.second = referenceComponents.second
        components.nanosecond = referenceComponents.nanosecond

        return calendar.date(from: components) ?? monthStart
    }
}
struct CashflowIncomeTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let initialHistoryCardID: String?

    init(viewModel: CashflowViewModel, initialHistoryCardID: String? = nil) {
        self.viewModel = viewModel
        self.initialHistoryCardID = initialHistoryCardID
    }

    var body: some View {
        CashflowCategoryTransactionSheet(
            viewModel: viewModel,
            kind: .income,
            initialHistoryCardID: initialHistoryCardID
        )
    }
}

struct CashflowExpenseTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel
    let initialHistoryCardID: String?

    init(viewModel: CashflowViewModel, initialHistoryCardID: String? = nil) {
        self.viewModel = viewModel
        self.initialHistoryCardID = initialHistoryCardID
    }

    var body: some View {
        CashflowCategoryTransactionSheet(
            viewModel: viewModel,
            kind: .expense,
            initialHistoryCardID: initialHistoryCardID
        )
    }
}

struct CashflowTransferTransactionSheet: View {
    @ObservedObject var viewModel: CashflowViewModel

    var body: some View {
        CashflowTransactionEditorView(
            viewModel: viewModel,
            transactionType: .transfer,
            showsTransactionTypeSection: false,
            customNavigationTitle: L("cashflow.operation.new_transfer")
        )
    }
}
