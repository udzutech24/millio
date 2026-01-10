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
                            gradient: AppColors.waterGradient
                        )
                        
                        FeatureCard(
                            icon: "sparkles",
                            title: "8 сервисов",
                            description: "Финансы, курсы, кешбэк и многое другое",
                            gradient: AppColors.financesGradient
                        )
                    }
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
                        .background {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(.ultraThinMaterial)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(
                                            LinearGradient(
                                                colors: AppColors.incomeGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            ),
                                            lineWidth: 2
                                        )
                                }
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .opacity(opacity)
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                scale = 1.0
                opacity = 1.0
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
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .frame(width: 56, height: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    }
                
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
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            AppColors.textPrimary.opacity(0.1),
                            lineWidth: 1
                        )
                }
        }
    }
}

#Preview {
    OnboardingView(
        appState: AppState(),
        router: AppRouter()
    )
}
