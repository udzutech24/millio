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
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    
    @State private var cardViewModel: CardViewModel?
    @State private var createdCardID: String? = nil
    @State private var showPaywallAlert: Bool = false
    @State private var paywallMessage: LocalizedTextResolver = .empty

    private var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
    }

    private var canAddProduct: Bool {
        EntitlementPolicy.canAddFinanceProduct(
            isPro: appState.isPro,
            currentProducts: currentFinanceProductCount
        )
    }
    
    var body: some View {
        Group {
            if !canAddProduct {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(
                        String(
                            format: String(localized: "monetization.finance.products.limit.hard_format"),
                            EntitlementPolicy.freeFinanceProductLimit
                        )
                    )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else if let cardViewModel = cardViewModel {
                CardEditorView(viewModel: cardViewModel)
                    .onChange(of: cardViewModel.state.editingCard) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCardID = newValue?.cardUniqueID
                        }
                    }
                    .onDisappear {
                        if let cardID = createdCardID {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .card,
                                accountID: cardID,
                                group: viewModel.state.selectedGroupForAccount
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        guard canAddProduct else {
                            paywallMessage = LocalizedTextResolver { locale in
                                String(
                                    format: AppLocalization.string("monetization.finance.products.limit.hard_format", locale: locale),
                                    locale: locale,
                                    EntitlementPolicy.freeFinanceProductLimit
                                )
                            }
                            showPaywallAlert = true
                            return
                        }
                        cardViewModel = CardViewModel(modelContext: modelContext)
                        cardViewModel?.handle(.addCard)
                    }
            }
        }
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "monetization.free_plan.title",
            message: paywallMessage,
            onSubscribe: {
                router.push(.subscription)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

struct FinanceCreateCreditView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    
    @State private var creditViewModel: CreditViewModel?
    @State private var createdCreditID: String? = nil
    @State private var showPaywallAlert: Bool = false
    @State private var paywallMessage: LocalizedTextResolver = .empty

    private var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
    }

    private var canAddProduct: Bool {
        EntitlementPolicy.canAddFinanceProduct(
            isPro: appState.isPro,
            currentProducts: currentFinanceProductCount
        )
    }
    
    var body: some View {
        Group {
            if !canAddProduct {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(
                        String(
                            format: String(localized: "monetization.finance.products.limit.hard_format"),
                            EntitlementPolicy.freeFinanceProductLimit
                        )
                    )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else if let creditViewModel = creditViewModel {
                CreditEditorView(viewModel: creditViewModel)
                    .onChange(of: creditViewModel.state.editingCredit) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdCreditID = newValue?.creditUniqueID
                        }
                    }
                    .onDisappear {
                        if let creditID = createdCreditID {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .credit,
                                accountID: creditID,
                                group: viewModel.state.selectedGroupForAccount
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        guard canAddProduct else {
                            paywallMessage = LocalizedTextResolver { locale in
                                String(
                                    format: AppLocalization.string("monetization.finance.products.limit.hard_format", locale: locale),
                                    locale: locale,
                                    EntitlementPolicy.freeFinanceProductLimit
                                )
                            }
                            showPaywallAlert = true
                            return
                        }
                        creditViewModel = CreditViewModel(modelContext: modelContext)
                        creditViewModel?.handle(.addCredit)
                    }
            }
        }
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "monetization.free_plan.title",
            message: paywallMessage,
            onSubscribe: {
                router.push(.subscription)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}

struct FinanceCreateInvestmentView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    
    @State private var investmentViewModel: InvestmentViewModel?
    @State private var createdInvestmentID: String? = nil
    @State private var showPaywallAlert: Bool = false
    @State private var paywallMessage: LocalizedTextResolver = .empty

    private var currentFinanceProductCount: Int {
        viewModel.state.availableCards.count
        + viewModel.state.availableCredits.count
        + viewModel.state.availableInvestments.count
    }

    private var canAddProduct: Bool {
        EntitlementPolicy.canAddFinanceProduct(
            isPro: appState.isPro,
            currentProducts: currentFinanceProductCount
        )
    }
    
    var body: some View {
        Group {
            if !canAddProduct {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppColors.textTertiary)
                    Text(
                        String(
                            format: String(localized: "monetization.finance.products.limit.hard_format"),
                            EntitlementPolicy.freeFinanceProductLimit
                        )
                    )
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
            } else if let investmentViewModel = investmentViewModel {
                InvestmentEditorView(viewModel: investmentViewModel)
                    .onChange(of: investmentViewModel.state.editingInvestment) { oldValue, newValue in
                        if oldValue == nil && newValue != nil {
                            createdInvestmentID = newValue?.investmentUniqueID
                        }
                    }
                    .onDisappear {
                        if let investmentID = createdInvestmentID {
                            viewModel.handle(.addAccountToGroup(
                                accountType: .investment,
                                accountID: investmentID,
                                group: viewModel.state.selectedGroupForAccount
                            ))
                        }
                    }
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .onAppear {
                        guard canAddProduct else {
                            paywallMessage = LocalizedTextResolver { locale in
                                String(
                                    format: AppLocalization.string("monetization.finance.products.limit.hard_format", locale: locale),
                                    locale: locale,
                                    EntitlementPolicy.freeFinanceProductLimit
                                )
                            }
                            showPaywallAlert = true
                            return
                        }
                        investmentViewModel = InvestmentViewModel(modelContext: modelContext)
                        investmentViewModel?.handle(.addInvestment)
                    }
            }
        }
        .premiumUpsellAlert(
            isPresented: $showPaywallAlert,
            titleKey: "monetization.free_plan.title",
            message: paywallMessage,
            onSubscribe: {
                router.push(.subscription)
                dismiss()
            },
            onCancel: { dismiss() }
        )
    }
}
