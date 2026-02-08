//
//  FinanceEditViews.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finance Edit Views

struct FinanceEditCardView: View {
    let card: Card
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var cardViewModel: CardViewModel?

    init(
        card: Card,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.card = card
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: cardViewModel.state.showCardEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        cardViewModel = CardViewModel(modelContext: modelContext)
                        cardViewModel?.handle(.editCard(card))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}

struct FinanceEditCreditView: View {
    let credit: Credit
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var creditViewModel: CreditViewModel?

    init(
        credit: Credit,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.credit = credit
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: creditViewModel.state.showCreditEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        creditViewModel = CreditViewModel(modelContext: modelContext)
                        creditViewModel?.handle(.editCredit(credit))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}

struct FinanceEditInvestmentView: View {
    let investment: Investment
    @ObservedObject var viewModel: FinanceViewModel
    let onClose: (() -> Void)?
    let onDelete: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var investmentViewModel: InvestmentViewModel?

    init(
        investment: Investment,
        viewModel: FinanceViewModel,
        onClose: (() -> Void)? = nil,
        onDelete: (() -> Void)? = nil
    ) {
        self.investment = investment
        self.viewModel = viewModel
        self.onClose = onClose
        self.onDelete = onDelete
    }
    
    var body: some View {
        Group {
            if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel, onClose: onClose, onDelete: onDelete)
                    .onChange(of: investmentViewModel.state.showInvestmentEditor) { oldValue, newValue in
                        if oldValue == true && newValue == false {
                            viewModel.handle(.loadAccounts)
                            viewModel.handle(.loadGroups)
                            Task { await recalculateAllGroupTotals() }
                            if let onClose {
                                onClose()
                            } else {
                                dismiss()
                            }
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        investmentViewModel = InvestmentViewModel(modelContext: modelContext)
                        investmentViewModel?.handle(.editInvestment(investment))
                    }
            }
        }
    }
    
    private func recalculateAllGroupTotals() async {
        for group in viewModel.state.groups {
            let currency = group.displayCurrency ?? viewModel.state.displayCurrency
            let total = await viewModel.calculateGroupTotal(group: group, in: currency)
            viewModel.handle(.setGroupTotal(group.groupUniqueID, total))
        }
        await viewModel.calculateTotalAmountAsync()
    }
}
