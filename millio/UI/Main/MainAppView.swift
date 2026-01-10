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
    
    var body: some View {
        NavigationStack(path: $router.navigationPath) {
            ZStack {
                GradientBackground()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Button {
                            router.push(.profile)
                        } label: {
                            Image(systemName: "person.circle")
                                .font(.system(size: 28))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        
                        Spacer()
                        
                        Button {
                            router.push(.subscription)
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
                        
                        Spacer()
                        
                        Button {
                            router.push(.notifications)
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell")
                                    .font(.system(size: 28))
                                    .foregroundStyle(AppColors.textPrimary)
                                
                                Circle()
                                    .fill(AppColors.notificationBadge)
                                    .frame(width: 10, height: 10)
                                    .offset(x: 4, y: -4)
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
                                router.push(.finances)
                            }
                            
                            ServiceButton(
                                title: "Курсы",
                                icon: "briefcase.fill",
                                gradientColors: AppColors.coursesGradient
                            ) {
                                router.push(.courses)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Кешбэк",
                                icon: "percent",
                                gradientColors: AppColors.cashbackGradient
                            ) {
                                router.push(.cashback)
                            }
                            
                            ServiceButton(
                                title: "Кредиты",
                                icon: "creditcard.fill",
                                gradientColors: AppColors.creditsGradient
                            ) {
                                router.push(.credits)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Вода",
                                icon: "drop.fill",
                                gradientColors: AppColors.waterGradient
                            ) {
                                router.push(.water)
                            }
                            
                            ServiceButton(
                                title: "Привычки",
                                icon: "clock.fill",
                                gradientColors: AppColors.habitsGradient
                            ) {
                                router.push(.habits)
                            }
                        }
                        
                        HStack(spacing: 16) {
                            ServiceButton(
                                title: "Картотека",
                                icon: "archivebox.fill",
                                gradientColors: AppColors.cardIndexGradient
                            ) {
                                router.push(.cardIndex)
                            }
                            
                            ServiceButton(
                                title: "Игры",
                                icon: "gamecontroller.fill",
                                gradientColors: AppColors.gamesGradient
                            ) {
                                router.push(.games)
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
        case .water:
            WaterView()
        case .habits:
            HabitsView()
        case .cardIndex:
            CardIndexView()
        case .games:
            GamesView()
        case .profile:
            ProfileView(router: router)
        case .notifications:
            NotificationsView()
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
