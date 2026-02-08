//
//  SubscriptionView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import StoreKit

struct SubscriptionView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var products: [Product] = []
    
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
                    
                    // Статус подписки (если уже есть)
                    if appState.isPro {
                        subscriptionStatusSection
                            .padding(.horizontal, 24)
                            .padding(.bottom, 24)
                    }
                    
                    // Кнопка пробного периода (если нет подписки)
                    if !appState.isPro && !appState.isTrialActive {
                        trialButton
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                    }
                    
                    // Кнопка подписки
                    Button {
                        Task {
                            await purchaseSubscription()
                        }
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
                    .disabled(isLoading)
                    .opacity(isLoading ? 0.6 : 1.0)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                    // Кнопка восстановления покупок
                    Button {
                        Task {
                            await restorePurchases()
                        }
                    } label: {
                        Text("Восстановить покупки")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .disabled(isLoading)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Подписка")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Ошибка", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? "Неизвестная ошибка")
        }
        .task {
            await loadProducts()
        }
    }
    
    // MARK: - Subscription Status Section
    
    private var subscriptionStatusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.incomeGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(appState.isTrialActive ? "Активен пробный период" : "Активна подписка PRO")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
            }
            
            if let expirationDate = appState.subscriptionExpirationDate {
                HStack {
                    Text("Действует до:")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                    
                    Text(formatDate(expirationDate))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: AppColors.incomeGradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                }
        )
    }
    
    // MARK: - Trial Button
    
    private var trialButton: some View {
        Button {
            Task {
                await startTrial()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("Начать пробный период (7 дней)")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 2
                            )
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
    
    // MARK: - Actions
    
    private func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let productIds = [
                SubscriptionManager.shared.monthlyProductID,
                SubscriptionManager.shared.yearlyProductID
            ]
            products = try await Product.products(for: productIds)
        } catch {
            errorMessage = "Не удалось загрузить продукты"
            showError = true
        }
    }
    
    private func purchaseSubscription() async {
        isLoading = true
        defer { isLoading = false }
        
        let productId = selectedPlan == .monthly
            ? SubscriptionManager.shared.monthlyProductID
            : SubscriptionManager.shared.yearlyProductID
        
        do {
            try await SubscriptionManager.shared.purchaseSubscription(productId: productId)
            
            // Обновляем статус в AppState
            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive
            
        } catch {
            if let subscriptionError = error as? SubscriptionError,
               subscriptionError != .userCancelled {
                errorMessage = subscriptionError.localizedDescription
                showError = true
            }
        }
    }
    
    private func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await SubscriptionManager.shared.restorePurchases()
            
            // Обновляем статус в AppState
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.subscriptionExpirationDate = SubscriptionManager.shared.expirationDate
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive
            
        } catch {
            errorMessage = "Не удалось восстановить покупки"
            showError = true
        }
    }
    
    private func startTrial() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await SubscriptionManager.shared.startTrial()
            
            // Обновляем статус в AppState
            appState.subscriptionStatus = SubscriptionManager.shared.status
            appState.isTrialActive = SubscriptionManager.shared.isTrialActive
            
        } catch {
            errorMessage = (error as? SubscriptionError)?.localizedDescription ?? "Не удалось начать пробный период"
            showError = true
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter.string(from: date)
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
                                lineWidth: 1
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
