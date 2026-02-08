//
//  FinanceCreateViews.swift
//  millio
//

import SwiftUI
import SwiftData

// MARK: - Finance Create Views

struct FinanceCreateCardView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var cardViewModel: CardViewModel?
    @State private var createdCardID: String? = nil
    
    var body: some View {
        Group {
            if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel)
                    .onChange(of: cardViewModel.state.editingCard) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCardID = newValue?.cardUniqueID
                        }
                    }
                    .onDisappear {
                        if let cardID = createdCardID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .card,
                                accountID: cardID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        cardViewModel = CardViewModel(modelContext: modelContext)
                        cardViewModel?.handle(.addCard)
                    }
            }
        }
    }
}

struct FinanceCreateCreditView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var creditViewModel: CreditViewModel?
    @State private var createdCreditID: String? = nil
    
    var body: some View {
        Group {
            if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel)
                    .onChange(of: creditViewModel.state.editingCredit) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCreditID = newValue?.creditUniqueID
                        }
                    }
                    .onDisappear {
                        if let creditID = createdCreditID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .credit,
                                accountID: creditID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        creditViewModel = CreditViewModel(modelContext: modelContext)
                        creditViewModel?.handle(.addCredit)
                    }
            }
        }
    }
}

struct FinanceCreateInvestmentView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var investmentViewModel: InvestmentViewModel?
    @State private var createdInvestmentID: String? = nil
    
    var body: some View {
        Group {
            if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel)
                    .onChange(of: investmentViewModel.state.editingInvestment) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdInvestmentID = newValue?.investmentUniqueID
                        }
                    }
                    .onDisappear {
                        if let investmentID = createdInvestmentID,
                           let targetGroup = viewModel.state.selectedGroupForAccount {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .investment,
                                accountID: investmentID,
                                group: targetGroup
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        investmentViewModel = InvestmentViewModel(modelContext: modelContext)
                        investmentViewModel?.handle(.addInvestment)
                    }
            }
        }
    }
}
