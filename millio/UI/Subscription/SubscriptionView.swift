//
//  SubscriptionView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct SubscriptionView: View {
    @State private var selectedPlan: SubscriptionPlan = .monthly
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 0) {
                    // Заголовок
                    VStack(spacing: 12) {
                        Text("millio PRO")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColors.textPrimary, AppColors.textSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("Расширенные возможности")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.top, 40)
                    .padding(.bottom, 32)
                    
                    // Выбор плана
                    VStack(spacing: 16) {
                        SubscriptionPlanCard(
                            plan: .monthly,
                            isSelected: selectedPlan == .monthly,
                            gradient: AppColors.expenseGradient
                        ) {
                            selectedPlan = .monthly
                        }
                        
                        SubscriptionPlanCard(
                            plan: .yearly,
                            isSelected: selectedPlan == .yearly,
                            gradient: AppColors.incomeGradient,
                            isPopular: true
                        ) {
                            selectedPlan = .yearly
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 32)
                    
                    // Преимущества
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Что включено")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            FeatureRow(
                                icon: "sparkles",
                                text: "Все 10 сервисов без ограничений",
                                gradient: AppColors.financesGradient
                            )
                            
                            FeatureRow(
                                icon: "chart.line.uptrend.xyaxis",
                                text: "Расширенная аналитика",
                                gradient: AppColors.coursesGradient
                            )
                        }
                        .padding(.horizontal, 24)
                    }
                    .padding(.bottom, 40)
                    
                    // Кнопка подписки
                    Button {
                        // TODO: Логика подписки
                    } label: {
                        HStack(spacing: 12) {
                            Text("Оформить подписку")
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
                }
            }
        }
        .navigationTitle("Подписка")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Subscription Plan

private enum SubscriptionPlan {
    case monthly
    case yearly
    
    var title: String {
        switch self {
        case .monthly: return "Месяц"
        case .yearly: return "Год"
        }
    }
    
    var price: String {
        switch self {
        case .monthly: return "299 ₽"
        case .yearly: return "2 490 ₽"
        }
    }
    
    var period: String {
        switch self {
        case .monthly: return "в месяц"
        case .yearly: return "в год"
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "Экономия 30%"
        }
    }
}

// MARK: - Subscription Plan Card

private struct SubscriptionPlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let gradient: [Color]
    let isPopular: Bool
    let action: () -> Void
    
    init(
        plan: SubscriptionPlan,
        isSelected: Bool,
        gradient: [Color],
        isPopular: Bool = false,
        action: @escaping () -> Void
    ) {
        self.plan = plan
        self.isSelected = isSelected
        self.gradient = gradient
        self.isPopular = isPopular
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                HStack {
                    if isPopular {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Популярно")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background {
                            Capsule()
                                .fill(.ultraThinMaterial)
                        }
                    }
                    
                    Spacer()
                    
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                    }
                }
                
                VStack(spacing: 4) {
                    Text(plan.title)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(plan.price)
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text(plan.period)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    
                    if let savings = plan.savings {
                        Text(savings)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.top, 4)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(
                                isSelected
                                ? LinearGradient(
                                    colors: gradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [AppColors.textPrimary.opacity(0.1)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: isSelected ? 2 : 1
                            )
                    }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let text: String
    let gradient: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .frame(width: 40, height: 40)
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
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
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(
                            AppColors.textPrimary.opacity(0.1),
                            lineWidth: 1
                        )
                }
        }
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
