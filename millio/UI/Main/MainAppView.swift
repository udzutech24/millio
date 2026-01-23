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
    @State private var cashflowViewModel: CashflowViewModel?
    @State private var showExpenseSheet = false
    @State private var showIncomeSheet = false
    
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
                        // Иконка профиля слева
                        Button {
                            viewModel.handle(.navigateToProfile)
                        } label: {
                            Image("profile")
                        }
                        
                        Spacer()
                        
                        // Кнопка PRO справа
                        Button {
                            viewModel.handle(.navigateToSubscription)
                        } label: {
                            HStack(spacing: 8) {
                                Image(appState.isPro ? "star" : "star")
                                    .font(.system(size: 14))
                                Text("PRO")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background {
                                Capsule()
                                    .stroke(
                                        LinearGradient(
                                            colors: appState.isPro
                                                ? [Color(hex: "19E694").opacity(0.5), Color(hex: "BD00E7").opacity(0.5)]
                                            : [Color(hex: "19E694").opacity(0.5), Color(hex: "BD00E7").opacity(0.5)],
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
                    VStack(alignment: .leading, spacing: 0) {
                        Text("millio")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(Color.white)
                        
                        Text("ваш лучший помощник")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Color.white)
                          
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 30)
                    
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
        let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
        
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(services) { service in
                ServiceButton(
                    title: service.title,
                    icon: service.icon,
                    gradientColors: service.gradientColors
                ) {
                    viewModel.handle(.navigateToService(service.route))
                }
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadServices() {
        // Временно показываем только основные сервисы
        let allowedIds = ["finances", "courses", "cashback", "cashflow"]
        services = ServiceItem.allServices().filter { allowedIds.contains($0.id) }
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
