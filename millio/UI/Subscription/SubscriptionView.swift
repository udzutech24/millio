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

    private var localizationLocale: Locale {
        appState.selectedLanguage.locale ?? Locale.current
    }

    private var isRunningInPreview: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    private var legalLinks: ProfileLegalLinks {
        ProfileLegalLinks.make(for: appState.selectedLanguage, fallbackLocale: localizationLocale)
    }

    private var manageSubscriptionURL: URL {
        URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    var body: some View {
        ZStack {
            subscriptionBackground

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    header
                    plansCard
                    benefitsSection
                    controlsSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, appState.isPro ? 24 : 112)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .top) {
            topBar
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.55), Color.black.opacity(0.0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .ignoresSafeArea()
                )
        }
        .safeAreaInset(edge: .bottom) {
            if !appState.isPro {
                subscribeButton
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .alert("subscription.alert.error.title", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage ?? String(localized: "subscription.error.unknown", locale: localizationLocale))
        }
        .task {
            guard !isRunningInPreview else { return }
            await loadProducts()
        }
        .environment(\.locale, localizationLocale)
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

                VStack(spacing: 18) {
                    heroTitleBlock
                    heroHighlightsRow
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
        }
    }

    private var heroTitleBlock: some View {
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

            VStack(spacing: 10) {
                Text("subscription.hero.eyebrow")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.6))
                    .textCase(.uppercase)
                    .tracking(1.4)

                Text("subscription.hero.title")
                    .font(.system(size: 42, weight: .black, design: .rounded))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("subscription.hero.subtitle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var heroStatBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.white.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }

    private var heroHighlightsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                ForEach(SubscriptionContent.heroHighlights) { item in
                    heroHighlightCard(item)
                }
            }

            VStack(spacing: 10) {
                ForEach(SubscriptionContent.heroHighlights) { item in
                    heroHighlightCard(item)
                }
            }
        }
    }

    private func heroHighlightCard(_ item: SubscriptionBenefitDescriptor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: AppLocalization.string(item.titleKey, locale: localizationLocale))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)

                Text(verbatim: AppLocalization.string(item.detailKey, locale: localizationLocale))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(heroStatBackground)
    }

    private var plansCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("subscription.plans.title")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.54))
                    .textCase(.uppercase)

                Text("subscription.plans.subtitle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 12) {
                ForEach(SubscriptionPlan.allCases) { plan in
                    planRow(for: plan)
                }
            }

            Text("subscription.plans.footnote")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.54))
                .fixedSize(horizontal: false, vertical: true)
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    planSelectionIndicator(for: plan)
                    planMainInfo(for: plan)
                    Spacer(minLength: 8)
                    planPriceInfo(for: plan)
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        planSelectionIndicator(for: plan)
                        planMainInfo(for: plan)
                    }

                    HStack {
                        Spacer(minLength: 0)
                        planPriceInfo(for: plan)
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

    private func planSelectionIndicator(for plan: SubscriptionPlan) -> some View {
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
    }

    private func planMainInfo(for plan: SubscriptionPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.titleKey)
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            planBadge(for: plan)
        }
    }

    @ViewBuilder
    private func planBadge(for plan: SubscriptionPlan) -> some View {
        if let badgeText = planBadgeText(for: plan) {
            Text(verbatim: badgeText)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "2B5CFF"), Color(hex: "50E07C")],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
        }
    }

    private func planPriceInfo(for plan: SubscriptionPlan) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            planPriceLabel(for: plan)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(plan.periodLabelKey)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.7))

        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var benefitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("subscription.features.title")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 0) {
                ForEach(Array(SubscriptionContent.benefits.enumerated()), id: \.element.id) { index, benefit in
                    benefitRow(benefit)

                    if index < SubscriptionContent.benefits.count - 1 {
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

    private func benefitRow(_ benefit: SubscriptionBenefitDescriptor) -> some View {
        HStack(alignment: .top, spacing: 14) {
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

            VStack(alignment: .leading, spacing: 5) {
                Text(verbatim: AppLocalization.string(benefit.titleKey, locale: localizationLocale))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(verbatim: AppLocalization.string(benefit.detailKey, locale: localizationLocale))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.62))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 6)

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

            legalSection
        }
    }

    private var legalSection: some View {
        VStack(spacing: 14) {
            WrappingHStack(alignment: .center, horizontalSpacing: 14, verticalSpacing: 10) {
                if appState.isPro {
                    Link(String(localized: "subscription.link.manage", locale: localizationLocale), destination: manageSubscriptionURL)
                }
                Link(legalLinks.privacyTitle, destination: legalLinks.privacyURL)
                Link(legalLinks.termsTitle, destination: legalLinks.termsURL)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)

            Text("subscription.legal.note")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.52))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task {
                    await restorePurchases()
                }
            } label: {
                Text("subscription.button.restore")
                    .font(.system(size: 15, weight: .medium))
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
                ctaTitle
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)

                Text(ctaSubtitleKey)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: appState.isTrialActive ? "sparkles" : "checkmark.circle.fill")
                    .foregroundStyle(appState.isTrialActive ? Color(hex: "70C7FF") : Color(hex: "4DD471"))

                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.isTrialActive ? "subscription.status.trial_active" : "subscription.status.subscribed_active")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(appState.isTrialActive ? "subscription.status.trial_detail" : "subscription.status.subscribed_detail")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.62))
                }
            }

            if let expirationDate = appState.subscriptionExpirationDate {
                HStack(spacing: 8) {
                    Text("subscription.status.expires_at")
                    Text(verbatim: formatDate(expirationDate))
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.78))
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

    private var ctaSubtitleKey: LocalizedStringKey {
        selectedPlan == .yearly ? "subscription.cta.subtitle.yearly" : "subscription.cta.subtitle.monthly"
    }

    private var ctaTitle: Text {
        let fallback = selectedPlan.fallbackTotalPrice
        let totalPrice = planTotalPrice(for: selectedPlan) ?? fallback
        return Text("subscription.button.subscribe") + Text(" ") + Text(verbatim: totalPrice)
    }

    private func planBadgeText(for plan: SubscriptionPlan) -> String? {
        switch plan {
        case .monthly:
            return nil
        case .yearly:
            if let savings = yearlySavingsPercentage {
                return String(
                    format: String(localized: "subscription.plan.yearly.savings_format", locale: localizationLocale),
                    savings
                )
            }
            return String(localized: "subscription.plan.yearly.savings", locale: localizationLocale)
        }
    }

    private func planPriceLabel(for plan: SubscriptionPlan) -> Text {
        Text(verbatim: planTotalPrice(for: plan) ?? plan.fallbackTotalPrice)
    }

    private func planTotalPrice(for plan: SubscriptionPlan) -> String? {
        guard let product = product(for: plan) else {
            return nil
        }

        return product.displayPrice
    }

    private func product(for plan: SubscriptionPlan) -> Product? {
        products.first { $0.id == plan.productID(monthlyID: SubscriptionManager.shared.monthlyProductID, yearlyID: SubscriptionManager.shared.yearlyProductID) }
    }

    private var yearlySavingsPercentage: Int? {
        guard
            let monthlyProduct = product(for: .monthly),
            let yearlyProduct = product(for: .yearly)
        else {
            return nil
        }

        let monthlyValue = NSDecimalNumber(decimal: monthlyProduct.price).doubleValue
        let yearlyValue = NSDecimalNumber(decimal: yearlyProduct.price).doubleValue
        guard monthlyValue > 0, yearlyValue > 0 else { return nil }

        let annualMonthlyValue = monthlyValue * 12
        guard annualMonthlyValue > yearlyValue else { return nil }

        let percent = ((annualMonthlyValue - yearlyValue) / annualMonthlyValue) * 100
        return max(1, Int(percent.rounded()))
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
            errorMessage = String(localized: "subscription.error.load_products", locale: localizationLocale)
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
                errorMessage = subscriptionError.localizedDescription(for: localizationLocale)
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
            errorMessage = String(localized: "subscription.error.restore_purchases", locale: localizationLocale)
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
            errorMessage = (error as? SubscriptionError)?.localizedDescription(for: localizationLocale)
                ?? String(localized: "subscription.error.start_trial", locale: localizationLocale)
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

    var titleKey: LocalizedStringKey {
        switch self {
        case .yearly: return "subscription.plan.yearly.title"
        case .monthly: return "subscription.plan.monthly.title"
        }
    }

    var periodLabelKey: LocalizedStringKey {
        switch self {
        case .yearly:
            return "subscription.plan.yearly.period"
        case .monthly:
            return "subscription.plan.monthly.period"
        }
    }

    var fallbackTotalPrice: String {
        switch self {
        case .yearly: return "2 490 ₽"
        case .monthly: return "299 ₽"
        }
    }

    func productID(monthlyID: String, yearlyID: String) -> String {
        switch self {
        case .yearly: return yearlyID
        case .monthly: return monthlyID
        }
    }
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

private enum SubscriptionViewPreview {
    @MainActor
    static func appState(language: Language) -> AppState {
        let appState = AppState()
        appState.selectedLanguage = language
        return appState
    }
}

#Preview("Subscription RU — Compact") {
    NavigationStack { SubscriptionView() }
        .environment(SubscriptionViewPreview.appState(language: .russian))
        .frame(width: 320, height: 820)
}

#Preview("Subscription EN — Compact") {
    NavigationStack { SubscriptionView() }
        .environment(SubscriptionViewPreview.appState(language: .english))
        .frame(width: 320, height: 820)
}

#Preview("Subscription RU — Large Text") {
    NavigationStack { SubscriptionView() }
        .environment(SubscriptionViewPreview.appState(language: .russian))
        .dynamicTypeSize(.accessibility1)
        .frame(width: 390, height: 900)
}
