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
                        Text("subscription.hero.title")
                            .font(.system(size: 42, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [AppColors.textPrimary, AppColors.textSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                        
                        Text("subscription.hero.subtitle")
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
                        Text("subscription.features.title")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 24)
                        
                        VStack(spacing: 12) {
                            FeatureRow(
                                icon: "sparkles",
                                textKey: "subscription.features.unlimited_services",
                                gradient: AppColors.financesGradient
                            )
                            
                            FeatureRow(
                                icon: "chart.line.uptrend.xyaxis",
                                textKey: "subscription.features.advanced_analytics",
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
                            Text("subscription.button.subscribe")
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
                        Text("subscription.button.restore")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .disabled(isLoading)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("subscription.navigation.title")
        .navigationBarTitleDisplayMode(.inline)
        .alert("subscription.alert.error.title", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? String(localized: "subscription.error.unknown"))
        }
        .task {
            await loadProducts()
        }
    }
    
    // MARK: - Subscription Status Section
    
    private var subscriptionStatusSection: some View {
        let gradient = AppColors.incomeGradient
        
        return VStack(spacing: 12) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                Text(appState.isTrialActive ? "subscription.status.trial_active" : "subscription.status.subscribed_active")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
            }
            
            if let expirationDate = appState.subscriptionExpirationDate {
                HStack {
                    Text("subscription.status.expires_at")
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
        .background(GlassBackground(gradient: gradient, cornerRadius: 16, strokeWidth: 1))
    }
    
    // MARK: - Trial Button
    
    private var trialButton: some View {
        let gradient = AppColors.cashbackGradient
        
        return Button {
            Task {
                await startTrial()
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 16, weight: .semibold))
                
                Text("subscription.button.start_trial")
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(GlassBackground(gradient: gradient, cornerRadius: 16, strokeWidth: 2))
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
            errorMessage = String(localized: "subscription.error.load_products")
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
            errorMessage = String(localized: "subscription.error.restore_purchases")
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
            errorMessage = (error as? SubscriptionError)?.localizedDescription ?? String(localized: "subscription.error.start_trial")
            showError = true
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        formatter.locale = appState.selectedLanguage.locale ?? Locale.current
        return formatter.string(from: date)
    }
}

// MARK: - Subscription Plan
// (No changes needed for Enum)
private enum SubscriptionPlan {
    case monthly
    case yearly
    
    var title: String {
        switch self {
        case .monthly: return String(localized: "subscription.plan.monthly.title")
        case .yearly: return String(localized: "subscription.plan.yearly.title")
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
        case .monthly: return String(localized: "subscription.plan.monthly.period")
        case .yearly: return String(localized: "subscription.plan.yearly.period")
        }
    }
    
    var savings: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return String(localized: "subscription.plan.yearly.savings")
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
                            Text("subscription.plan.popular")
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
            .background(GlassBackground(gradient: gradient, isActive: isSelected))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Feature Row

private struct FeatureRow: View {
    let icon: String
    let textKey: LocalizedStringKey
    let gradient: [Color]
    
    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                GlassBackground(gradient: gradient, cornerRadius: 12, strokeWidth: 1)
                    .frame(width: 40, height: 40)
                
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
            
            Text(textKey)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(AppColors.textPrimary)
            
            Spacer()
        }
        .padding(16)
        .background(GlassBackground(gradient: gradient, cornerRadius: 16, isActive: false))
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
