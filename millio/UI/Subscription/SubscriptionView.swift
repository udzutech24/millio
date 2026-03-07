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
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var products: [Product] = []

    private let benefits: [SubscriptionBenefit] = [
        .init(icon: "bitcoinsign.circle.fill", titleKey: "subscription.features.crypto_converter"),
        .init(icon: "text.viewfinder", titleKey: "subscription.features.cashback_screenshot"),
        .init(icon: "list.bullet.rectangle.portrait", titleKey: "subscription.features.cashback_categories"),
        .init(icon: "tray.full.fill", titleKey: "subscription.features.finance_products"),
        .init(icon: "chart.line.uptrend.xyaxis", titleKey: "subscription.features.finance_markets"),
        .init(icon: "chart.bar.fill", titleKey: "subscription.features.finance_charts")
    ]
    private let heroItems: [SubscriptionHeroFeature] = [
        .init(icon: "bitcoinsign.circle.fill", titleKey: "subscription.hero.card.crypto.title", subtitleKey: "subscription.hero.card.crypto.subtitle"),
        .init(icon: "text.viewfinder", titleKey: "subscription.hero.card.cashback.title", subtitleKey: "subscription.hero.card.cashback.subtitle"),
        .init(icon: "chart.xyaxis.line", titleKey: "subscription.hero.card.charts.title", subtitleKey: "subscription.hero.card.charts.subtitle")
    ]

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                subscriptionBackground

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        topBar
                        header
                        plansCard
                        benefitsSection
                        controlsSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, max(10, topInset + 6))
                    .padding(.bottom, 132)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .safeAreaInset(edge: .bottom) {
            subscribeButton
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("subscription.alert.error.title", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? String(localized: "subscription.error.unknown"))
        }
        .task {
            await loadProducts()
        }
    }

    private var subscriptionBackground: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PremiumStarsBackground()

            LinearGradient(
                colors: [
                    Color(hex: "153A89").opacity(0.34),
                    Color(hex: "3B1E68").opacity(0.18),
                    .clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack {
                Ellipse()
                    .fill(Color(hex: "79C7FF").opacity(0.12))
                    .frame(width: 320, height: 160)
                    .blur(radius: 28)
                    .offset(y: -42)
                Spacer()
            }
            .ignoresSafeArea()
        }
    }

    private var topBar: some View {
        HStack {
            backButton

            Spacer()

            Text("subscription.navigation.title")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.7))

            Spacer()

            Circle()
                .fill(Color.clear)
                .frame(width: 44, height: 44)
        }
    }

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial.opacity(0.55))
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))

                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white)
            }
        }
        .frame(width: 44, height: 44)
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 34, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 1)
                    )

                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [Color(hex: "70C7FF").opacity(0.38), .clear],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 58
                                )
                            )
                            .frame(width: 120, height: 120)

                        Image("crown")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 110, height: 90)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 8) {
                        Text("subscription.hero.title")
                            .font(.system(size: 42, weight: .black, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("subscription.hero.subtitle")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.68))
                            .multilineTextAlignment(.center)
                    }

                    heroHighlights
                    heroFeatureCards
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
    }

    private var heroHighlights: some View {
        HStack(spacing: 10) {
            subscriptionPill(icon: "crown.fill", text: String(localized: "subscription.hero.pill.value"))
            subscriptionPill(icon: "lock.open.display", text: String(localized: "subscription.hero.pill.unlock"))
            subscriptionPill(icon: "bolt.badge.checkmark.fill", text: String(localized: "subscription.hero.pill.smart"))
        }
    }

    private func subscriptionPill(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(Color.white.opacity(0.78))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.07))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var heroFeatureCards: some View {
        HStack(spacing: 10) {
            ForEach(heroItems) { item in
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))

                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 42, height: 42)

                    Text(item.titleKey)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(item.subtitleKey)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                )
            }
        }
    }

    private var plansCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("subscription.plans.title")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.54))
                .textCase(.uppercase)

            VStack(spacing: 12) {
                ForEach(SubscriptionPlan.allCases) { plan in
                    planRow(for: plan)
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func planRow(for plan: SubscriptionPlan) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.35), lineWidth: 2)
                        .frame(width: 34, height: 34)

                    if selectedPlan == plan {
                        Circle()
                            .fill(Color(hex: "50E07C"))
                            .frame(width: 34, height: 34)

                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 21, weight: .bold))
                            .foregroundStyle(.white)

                        if let badge = plan.badge {
                            Text(badge)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color(hex: "4DD471"))
                                .clipShape(Capsule())
                        }
                    }

                    Text(planSubtitle(for: plan))
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color.white.opacity(0.65))
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(planPriceLabel(for: plan))
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    if selectedPlan == plan {
                        Text("subscription.plan.popular")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(selectedPlan == plan ? Color.white.opacity(0.12) : Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .stroke(
                                selectedPlan == plan ? Color.white.opacity(0.24) : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("subscription.features.title")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)

                Text("subscription.features.subtitle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))
            }

            VStack(spacing: 0) {
                ForEach(Array(benefits.enumerated()), id: \.offset) { index, benefit in
                    benefitRow(benefit)

                    if index < benefits.count - 1 {
                        Divider()
                            .overlay(Color.white.opacity(0.08))
                            .padding(.leading, 64)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 32, style: .continuous)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
        }
    }

    private func benefitRow(_ benefit: SubscriptionBenefit) -> some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "FFA84D"), Color(hex: "FF694D")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)
                .overlay {
                    Image(systemName: benefit.icon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }

            Text(benefit.titleKey)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)

            Spacer()
        }
        .padding(.vertical, 14)
    }

    private var controlsSection: some View {
        VStack(spacing: 14) {
            if appState.isPro {
                subscriptionStatusSection
            }

            if !appState.isPro && !appState.isTrialActive {
                trialButton
            }

            Button {
                Task {
                    await restorePurchases()
                }
            } label: {
                Text("subscription.button.restore")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private var subscribeButton: some View {
        Button {
            Task {
                await purchaseSubscription()
            }
        } label: {
            VStack(spacing: 4) {
                Text(ctaTitle)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)

                Text("subscription.cta.subtitle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(
                LinearGradient(
                    colors: [Color(hex: "2A8CFF"), Color(hex: "4B76FF"), Color(hex: "7D72FF")],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: Color(hex: "2A8CFF").opacity(0.24), radius: 20, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .opacity(isLoading ? 0.55 : 1)
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial.opacity(0.82))
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.5)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        )
    }

    private var subscriptionStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "4DD471"))

                Text(appState.isTrialActive ? "subscription.status.trial_active" : "subscription.status.subscribed_active")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }

            if let expirationDate = appState.subscriptionExpirationDate {
                Text("\(String(localized: "subscription.status.expires_at")): \(formatDate(expirationDate))")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.09), lineWidth: 1)
                )
        )
    }

    private var trialButton: some View {
        Button {
            Task {
                await startTrial()
            }
        } label: {
            Text("subscription.button.start_trial")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private var ctaTitle: String {
        let fallback = selectedPlan.fallbackTotalPrice
        let totalPrice = planTotalPrice(for: selectedPlan) ?? fallback
        return "\(String(localized: "subscription.button.subscribe")) \(totalPrice)"
    }

    private func planPriceLabel(for plan: SubscriptionPlan) -> String {
        if let label = perMonthPriceLabel(for: plan) {
            return label
        }

        return plan.fallbackPerMonthPrice
    }

    private func planSubtitle(for plan: SubscriptionPlan) -> String {
        let totalPrice = planTotalPrice(for: plan) ?? plan.fallbackTotalPrice
        return "\(plan.periodLabel) • \(totalPrice)"
    }

    private func planTotalPrice(for plan: SubscriptionPlan) -> String? {
        guard let product = product(for: plan) else {
            return nil
        }

        return product.displayPrice
    }

    private func perMonthPriceLabel(for plan: SubscriptionPlan) -> String? {
        guard let product = product(for: plan) else {
            return nil
        }

        let total = NSDecimalNumber(decimal: product.price)
        let divisor = NSDecimalNumber(value: plan.months)
        guard divisor != .zero else {
            return nil
        }

        let perMonth = total.dividing(by: divisor).decimalValue
        let currencyCode = product.priceFormatStyle.currencyCode
        let monthly = perMonth.formatted(.currency(code: currencyCode))
        return "\(monthly)/мес"
    }

    private func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.productID(monthlyID: SubscriptionManager.shared.monthlyProductID, yearlyID: SubscriptionManager.shared.yearlyProductID) }
    }

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

        do {
            try await SubscriptionManager.shared.purchaseSubscription(
                productId: selectedPlan.productID(
                    monthlyID: SubscriptionManager.shared.monthlyProductID,
                    yearlyID: SubscriptionManager.shared.yearlyProductID
                )
            )

            await SubscriptionManager.shared.checkSubscriptionStatus()
            appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)

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
            appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)

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
            appState.applySubscriptionSnapshot(SubscriptionManager.shared.snapshot)

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

enum SubscriptionPlan: CaseIterable, Identifiable {
    case yearly
    case monthly

    var id: Self { self }

    var title: String {
        switch self {
        case .yearly: return String(localized: "subscription.plan.yearly.title")
        case .monthly: return String(localized: "subscription.plan.monthly.title")
        }
    }

    var badge: String? {
        switch self {
        case .yearly: return String(localized: "subscription.plan.yearly.savings")
        case .monthly: return nil
        }
    }

    var periodLabel: String {
        switch self {
        case .yearly:
            return String(localized: "subscription.plan.yearly.period")
        case .monthly:
            return String(localized: "subscription.plan.monthly.period")
        }
    }

    var months: Int {
        switch self {
        case .yearly: return 12
        case .monthly: return 1
        }
    }

    var fallbackTotalPrice: String {
        switch self {
        case .yearly: return "2 490 ₽"
        case .monthly: return "299 ₽"
        }
    }

    var fallbackPerMonthPrice: String {
        switch self {
        case .yearly: return "207,50 ₽/мес"
        case .monthly: return "299 ₽/мес"
        }
    }

    func productID(monthlyID: String, yearlyID: String) -> String {
        switch self {
        case .yearly: return yearlyID
        case .monthly: return monthlyID
        }
    }
}

private struct SubscriptionBenefit {
    let icon: String
    let titleKey: LocalizedStringKey
}

private struct SubscriptionHeroFeature: Identifiable {
    let id = UUID()
    let icon: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
}

private struct PremiumStarsBackground: View {
    private struct StarPoint: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
        let size: Double
        let opacity: Double
    }

    private let points: [StarPoint] = {
        var generator = SeededGenerator(seed: 42)
        return (0..<170).map { _ in
            StarPoint(
                x: Double.random(in: 0...1, using: &generator),
                y: Double.random(in: 0...1, using: &generator),
                size: Double.random(in: 1.0...4.0, using: &generator),
                opacity: Double.random(in: 0.2...0.9, using: &generator)
            )
        }
    }()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RadialGradient(
                    colors: [Color(hex: "4D35B3").opacity(0.22), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: geometry.size.height * 0.65
                )

                ForEach(points) { point in
                    Circle()
                        .fill(Color(hex: "A76CFF").opacity(point.opacity))
                        .frame(width: point.size, height: point.size)
                        .position(
                            x: point.x * geometry.size.width,
                            y: point.y * geometry.size.height
                        )
                }
            }
            .ignoresSafeArea()
        }
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

#Preview {
    NavigationStack {
        SubscriptionView()
    }
}
