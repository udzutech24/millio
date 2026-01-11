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
    @StateObject private var viewModel: MainAppViewModel
    
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
                                Image(systemName: "star.fill")
                                    .font(.system(size: 14))
                                Text("PRO")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                Capsule()
                                    .stroke(AppColors.textPrimary, lineWidth: 1.5)
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
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Финансы",
                                icon: "wallet.pass.fill",
                                gradientColors: AppColors.financesGradient
                            ) {
                                viewModel.handle(.navigateToService(.finances))
                            }
                            
                            ServiceButton(
                                title: "Курсы",
                                icon: "briefcase.fill",
                                gradientColors: AppColors.coursesGradient
                            ) {
                                viewModel.handle(.navigateToService(.courses))
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Кешбэк",
                                icon: "percent",
                                gradientColors: AppColors.cashbackGradient
                            ) {
                                viewModel.handle(.navigateToService(.cashback))
                            }
                            
                            ServiceButton(
                                title: "Кредиты",
                                icon: "creditcard.fill",
                                gradientColors: AppColors.creditsGradient
                            ) {
                                viewModel.handle(.navigateToService(.credits))
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Привычки",
                                icon: "clock.fill",
                                gradientColors: AppColors.habitsGradient
                            ) {
                                viewModel.handle(.navigateToService(.habits))
                            }
                            
                            ServiceButton(
                                title: "Карты",
                                icon: "archivebox.fill",
                                gradientColors: AppColors.cardIndexGradient
                            ) {
                                viewModel.handle(.navigateToService(.cardIndex))
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Долги",
                                icon: "list.bullet.rectangle",
                                gradientColors: AppColors.debtsGradient
                            ) {
                                viewModel.handle(.navigateToService(.debts))
                            }
                            
                            ServiceButton(
                                title: "Активы",
                                icon: "chart.line.uptrend.xyaxis",
                                gradientColors: AppColors.investmentsGradient
                            ) {
                                viewModel.handle(.navigateToService(.investments))
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    Spacer()
                    
                    // Bottom action buttons
                    HStack(spacing: 16) {
                        ActionButton(
                            title: "Расход",
                            icon: "minus",
                            gradientColors: AppColors.expenseGradient
                        ) {
                            // TODO: Navigate to expense screen
                        }
                        
                        ActionButton(
                            title: "Доход",
                            icon: "plus",
                            gradientColors: AppColors.incomeGradient
                        ) {
                            // TODO: Navigate to income screen
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: AppRoute.self) { route in
                routeView(for: route)
            }
        }
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
