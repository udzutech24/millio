//
//  MainAppView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct MainAppView: View {
    @Bindable var router: AppRouter
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel: MainAppViewModel
    @State private var services: [ServiceItem] = []
    @State private var draggedItem: ServiceItem?
    @State private var cashflowViewModel: CashflowViewModel?
    @State private var showExpenseSheet = false
    @State private var showIncomeSheet = false
    
    private let orderManager = ServiceOrderManager()
    
    init(router: AppRouter) {
        self.router = router
        _viewModel = StateObject(wrappedValue: MainAppViewModel(router: router))
    }
    
    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            viewModel.handle(.navigateToProfile)
                        } label: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Button {
                            viewModel.handle(.navigateToSubscription)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: appState.isPro ? "star.fill" : "star")
                                    .font(.system(size: 14))
                                Text(appState.isPro ? "PRO" : "PRO")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(
                                appState.isPro
                                ? LinearGradient(
                                    colors: AppColors.incomeGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [AppColors.textPrimary],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .stroke(
                                        appState.isPro
                                        ? LinearGradient(
                                            colors: AppColors.incomeGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        : LinearGradient(
                                            colors: [AppColors.textPrimary],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    
                    // Title and slogan
                    VStack(spacing: 8) {
                        Text("millio")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("ваш лучший помощник")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 32)
                    .padding(.bottom, 40)
                    
                    // Service buttons grid
                    servicesGrid
                        .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Bottom action buttons
                    HStack(spacing: 16) {
                        ActionButton(
                            title: "Расход",
                            icon: "minus",
                            gradientColors: AppColors.expenseGradient
                        ) {
                            showExpenseSheet = true
                        }
                        
                        ActionButton(
                            title: "Доход",
                            icon: "plus",
                            gradientColors: AppColors.incomeGradient
                        ) {
                            showIncomeSheet = true
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                routeView(for: route)
            }
            .sheet(isPresented: $showExpenseSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowTransactionEditorView(
                        viewModel: cashflowViewModel,
                        transactionType: .expense
                    )
                }
            }
            .sheet(isPresented: $showIncomeSheet) {
                if let cashflowViewModel = cashflowViewModel {
                    CashflowTransactionEditorView(
                        viewModel: cashflowViewModel,
                        transactionType: .income
                    )
                }
            }
            .onAppear {
                loadServices()
                if cashflowViewModel == nil {
                    cashflowViewModel = CashflowViewModel(modelContext: modelContext)
                }
                
                // Обновляем статус подписки при открытии главного экрана
                Task {
                    await SubscriptionManager.shared.checkSubscriptionStatus()
                    appState.subscriptionStatus = SubscriptionManager.shared.status
                    appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
                    appState.isTrialActive = SubscriptionManager.shared.isTrialActive
                }
            }
        }
    }
    
    // MARK: - Services Grid
    
    private var servicesGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
        
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(services) { service in
                ServiceButton(
                    title: service.title,
                    icon: service.icon,
                    gradientColors: service.gradientColors
                ) {
                    viewModel.handle(.navigateToService(service.route))
                }
                .draggable(service.id) {
                    ServiceButton(
                        title: service.title,
                        icon: service.icon,
                        gradientColors: service.gradientColors
                    ) {
                        // Пустой action для drag preview
                    }
                    .opacity(0.8)
                }
                .dropDestination(for: String.self) { droppedIDs, location in
                    guard let droppedID = droppedIDs.first,
                          droppedID != service.id,
                          let draggedIndex = services.firstIndex(where: { $0.id == droppedID }),
                          let targetIndex = services.firstIndex(where: { $0.id == service.id }) else {
                        return false
                    }
                    
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        services.move(fromOffsets: IndexSet(integer: draggedIndex), toOffset: targetIndex > draggedIndex ? targetIndex + 1 : targetIndex)
                        saveServicesOrder()
                    }
                    
                    return true
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadServices() {
        services = orderManager.getOrderedServices()
    }
    
    private func saveServicesOrder() {
        let order = services.map { $0.id }
        orderManager.saveOrder(order)
    }
    
    @ViewBuilder
    private func routeView(for route: AppRoute) -> some View {
        switch route {
        case .finances:
            FinancesView()
        case .courses:
            CoursesView()
        case .cashback:
            CashbackView()
        case .credits:
            CreditsView()
        case .habits:
            HabitsView()
        case .cardIndex:
            CardIndexView()
        case .debts:
            DebtsView()
        case .investments:
            InvestmentsView()
        case .plannedExpenses:
            PlannedExpensesView()
        case .cashflow:
            CashflowView()
        case .profile:
            ProfileView(router: router)
        case .subscription:
            SubscriptionView()
        default:
            EmptyView()
        }
    }
}

#Preview {
    MainAppView(router: AppRouter())
        .environment(AppState())
}
