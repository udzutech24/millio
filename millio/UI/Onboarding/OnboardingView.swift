//
//  OnboardingView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Bindable var router: AppRouter
    @Environment(\.modelContext) private var modelContext
    
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.5
    @State private var showCurrencySettings = false
    @State private var favoriteCurrencyCodes: [String] = SettingsManager.shared.favoriteCurrencyCodes
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 60)
                    
                    // Логотип и заголовок
                    VStack(spacing: 16) {
                        Text("millio")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColors.textPrimary, AppColors.textSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(scale)
                            .opacity(opacity)
                        
                        Text("ваш лучший помощник")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                            .opacity(opacity)
                    }
                    .padding(.bottom, 48)
                    
                    // Карточки с возможностями
                    VStack(spacing: 16) {
                        FeatureCard(
                            icon: "lock.shield.fill",
                            title: "Безопасность",
                            description: "Ваши данные защищены и хранятся локально",
                            gradient: AppColors.creditsGradient
                        )
                        
                        FeatureCard(
                            icon: "icloud.fill",
                            title: "Резервное копирование",
                            description: "Автоматическое сохранение в iCloud",
                            gradient: AppColors.cashbackGradient
                        )
                        
                        FeatureCard(
                            icon: "sparkles",
                            title: "10 сервисов",
                            description: "Финансы, кэшфлоу, курсы и многое другое",
                            gradient: AppColors.financesGradient
                        )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 20)
                    .opacity(opacity)

                    VStack(spacing: 12) {
                        HStack {
                            Text("Основная валюта")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(appState.primaryCurrencyCode)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textSecondary)
                        }

                        HStack(alignment: .top, spacing: 8) {
                            Text("Избранные")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text(favoriteCurrencyCodes.joined(separator: ", "))
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                                .multilineTextAlignment(.trailing)
                        }

                        Button {
                            showCurrencySettings = true
                        } label: {
                            Text("Настроить валюты")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(GlassBackground(gradient: AppColors.financesGradient, strokeWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(20)
                    .background(GlassBackground(gradient: AppColors.financesGradient))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 48)
                    .opacity(opacity)
                    
                    // Кнопка "Начать"
                    Button {
                        completeOnboarding()
                    } label: {
                        HStack(spacing: 12) {
                            Text("Начать")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(GlassBackground(gradient: AppColors.incomeGradient, strokeWidth: 2))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(opacity)
                }
            }
        }
        .onAppear {
            favoriteCurrencyCodes = SettingsManager.shared.favoriteCurrencyCodes
            withAnimation(.easeOut(duration: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
        .sheet(isPresented: $showCurrencySettings, onDismiss: {
            favoriteCurrencyCodes = SettingsManager.shared.favoriteCurrencyCodes
        }) {
            NavigationStack {
                PrimaryCurrencySelectionView(primaryCurrencyCode: Binding(
                    get: { appState.primaryCurrencyCode },
                    set: { appState.primaryCurrencyCode = $0 }
                ))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Готово") {
                            showCurrencySettings = false
                        }
                    }
                }
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        appState.lifecycle = .ready
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let gradient: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            // Иконка
            ZStack {
                GlassBackground(
                    gradient: gradient,
                    cornerRadius: 16,
                    strokeWidth: 1
                )
                .frame(width: 56, height: 56)
                
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Текст
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Text(description)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(2)
            }
            
            Spacer()
        }
        .padding(20)
        .background(GlassBackground(gradient: gradient))
    }
}

#Preview {
    OnboardingView(
        appState: AppState(),
        router: AppRouter()
    )
}
