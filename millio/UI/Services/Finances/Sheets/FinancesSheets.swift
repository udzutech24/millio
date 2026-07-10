//
//  FinancesSheets.swift
//  millio
//

import SwiftUI

// MARK: - Sheets Modifier

struct SheetsModifier: ViewModifier {
    @ObservedObject var viewModel: FinanceViewModel
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupEditor },
                set: { if !$0 { viewModel.handle(.hideGroupEditor) } }
            )) {
                FinanceGroupEditorView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAddAccountSheet },
                set: { if !$0 { viewModel.handle(.hideAddAccountSheet) } }
            )) {
                FinanceAddAccountView(viewModel: viewModel)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: false)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSecondaryDisplayCurrencySheet },
                set: { if !$0 { viewModel.handle(.hideSecondaryDisplayCurrencySheet) } }
            )) {
                DisplayCurrencySheet(viewModel: viewModel, isSecondary: true)
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showQuickEditAccountSheet },
                set: { if !$0 { viewModel.handle(.hideQuickEditAccountSheet) } }
            )) {
                if let account = viewModel.state.quickEditAccount {
                    FinanceQuickEditAccountView(account: account, viewModel: viewModel)
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showGroupDynamics },
                set: { if !$0 { viewModel.handle(.hideGroupDynamics) } }
            )) {
                if let group = viewModel.state.selectedGroupForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialGroupID: group.groupUniqueID,
                        initialGroupCurrency: group.displayCurrency
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showAccountDynamics },
                set: { if !$0 { viewModel.handle(.hideAccountDynamics) } }
            )) {
                if let account = viewModel.state.selectedAccountForDynamics {
                    FinanceDynamicsView(
                        financeViewModel: viewModel,
                        initialAccountID: account.accountUniqueID,
                        initialAccountCurrency: viewModel.getAccountInfo(account: account)?.currency,
                        initialAccount: account
                    )
                }
            }
            .sheet(isPresented: Binding(
                get: { viewModel.state.showSavingsGoalSheet },
                set: { if !$0 { viewModel.handle(.hideSavingsGoalSheet) } }
            )) {
                SavingsGoalSettingsView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(.ultraThinMaterial)
            }
    }
}

// MARK: - Display Currency Sheet

struct DisplayCurrencySheet: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("finance_display_currency_hint_seen") private var hasSeenDisplayCurrencyHint: Bool = false
    var isSecondary: Bool = false
    @State private var searchText: String = ""
    @State private var showInfoBanner: Bool = false
    @State private var showInfoAlert: Bool = false
    @State private var showCryptoProAlert: Bool = false
    
    // Используем полный список валют из CurrencySelectionSupport
    private let allCurrencies = CurrencySelectionSupport.allCodes(includeCrypto: true)
    
    var body: some View {
        let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
        let canUseCrypto = EntitlementPolicy.canUseFinanceCrypto(isPro: appState.isPro)
        return NavigationStack {
            CurrencyPickerView(
                allCodes: allCurrencies,
                searchText: $searchText,
                selectedCodes: favoriteCodes,
                favoriteCodes: Set(favoriteCodes),
                currentSelection: isSecondary ? viewModel.state.secondaryDisplayCurrency : viewModel.state.displayCurrency,
                primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                onToggleFavorite: nil,
                badgeForCode: { code in
                    guard CurrencySelectionSupport.isCrypto(code), !canUseCrypto else { return nil }
                    return .pro
                },
                onSelect: { currency in
                    if CurrencySelectionSupport.isCrypto(currency), !canUseCrypto {
                        showCryptoProAlert = true
                        return
                    }
                    if isSecondary {
                        viewModel.handle(.setSecondaryDisplayCurrency(currency))
                    } else {
                        viewModel.handle(.setDisplayCurrency(currency))
                    }
                    dismiss()
                }
            )
            .safeAreaInset(edge: .top) {
                if showInfoBanner {
                    infoBanner(message: infoMessage)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
            .navigationTitle(
                isSecondary
                    ? L("finances.display_currency.title.secondary")
                    : L("finances.display_currency.title.primary")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("finances.common.cancel")) { dismiss() }
                        .foregroundStyle(AppColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfoAlert = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .accessibilityLabel(L("finances.display_currency.hint.accessibility"))
                }
            }
            .onAppear {
                if !hasSeenDisplayCurrencyHint {
                    showInfoBanner = true
                    hasSeenDisplayCurrencyHint = true
                }
            }
            .alert(L("finances.display_currency.hint.title"), isPresented: $showInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage)
            }
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: .key("monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var infoMessage: String {
        L("finances.display_currency.hint.message")
    }

    private func infoBanner(message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 1)

            Text(message)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)

            Button {
                showInfoBanner = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 18, height: 18)
                    .background(Color.white.opacity(0.08))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("finances.display_currency.hint.dismiss_accessibility"))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
    }
}

// MARK: - Savings Goal Settings View

struct SavingsGoalSettingsView: View {
    @ObservedObject var viewModel: FinanceViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEnabled: Bool = false
    @State private var goalAmount: String = ""
    @State private var goalAmountDisplayText: String = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()

                VStack(spacing: 20) {
                    // Настройки цели
                    VStack(alignment: .leading, spacing: 10) {
                        FinancesSectionHeader(title: FinancesL10n.tr("finances.savings_goal.settings_section"))
                        FinancesGlassCard(contentPadding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
                            Toggle(FinancesL10n.tr("finances.savings_goal.enabled"), isOn: $isEnabled)
                                .tint(AppColors.toggleOnGreen)
                                .foregroundStyle(AppColors.textPrimary)
                        }
                    }

                    if isEnabled {
                        // Сумма цели
                        VStack(alignment: .leading, spacing: 10) {
                            FinancesSectionHeader(title: FinancesL10n.format("finances.savings_goal.amount_section", viewModel.state.displayCurrency))
                            FinancesGlassCard {
                                TextField(FinancesL10n.tr("finances.savings_goal.amount_placeholder"), text: $goalAmountDisplayText)
                                    .keyboardType(.decimalPad)
                                    .foregroundStyle(AppColors.textPrimary)
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                            }
                        }

                        // Прогресс
                        if let amount = AmountInputFormatter.parse(goalAmount), amount > 0 {
                            let progress: Double = {
                                guard amount > 0 else { return 0.0 }
                                let calculated = viewModel.state.totalAmount / amount
                                guard calculated.isFinite else { return 0.0 }
                                return max(0.0, min(1.0, calculated))
                            }()
                            let remaining = max(0, amount - viewModel.state.totalAmount)

                            VStack(alignment: .leading, spacing: 10) {
                                FinancesSectionHeader(title: FinancesL10n.tr("finances.savings_goal.progress_section"))
                                FinancesGlassCard(contentPadding: EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)) {
                                    VStack(alignment: .leading, spacing: 16) {
                                        VStack(spacing: 8) {
                                            HStack {
                                                Text(FinancesL10n.tr("finances.savings_goal.current_amount"))
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(AppColors.textSecondary)
                                                Spacer()
                                                Text("\(formatAmount(viewModel.state.totalAmount, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                            }

                                            HStack {
                                                Text(FinancesL10n.tr("finances.savings_goal.remaining"))
                                                    .font(.system(size: 14, weight: .medium))
                                                    .foregroundStyle(AppColors.textSecondary)
                                                Spacer()
                                                Text("\(formatAmount(remaining, isHidden: viewModel.state.isAmountHidden)) \(viewModel.state.displayCurrency)")
                                                    .font(.system(size: 14, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                            }
                                        }

                                        // Кастомный прогресс бар
                                        VStack(spacing: 8) {
                                            GeometryReader { proxy in
                                                ZStack(alignment: .leading) {
                                                    Capsule()
                                                        .fill(Color.white.opacity(0.1))
                                                        .frame(height: 8)

                                                    Capsule()
                                                        .fill(LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing))
                                                        .frame(width: max(0, min(proxy.size.width, proxy.size.width * progress)), height: 8)
                                                }
                                            }
                                            .frame(height: 8)

                                            Text(FinancesL10n.format("finances.savings_goal.completed_percent", Int(progress * 100)))
                                                .font(.system(size: 12, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                                .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
            }
            .navigationTitle(FinancesL10n.tr("finances.savings_goal.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.white.opacity(0.06))
                        .frame(height: 1)
                        .opacity(0.45)

                    Button(action: saveGoalSettings) {
                        Text(FinancesL10n.tr("finances.common.save"))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: AppColors.financesGradient,
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ))
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 10)
                }
                .background(.ultraThinMaterial)
            }
            .onAppear {
                isEnabled = viewModel.state.isSavingsGoalEnabled
                if viewModel.state.savingsGoalAmount > 0 {
                    goalAmount = AmountInputFormatter.sanitize(
                        AmountInputFormatter.plainString(from: viewModel.state.savingsGoalAmount),
                        maxFractionDigits: 0
                    )
                    goalAmountDisplayText = AmountInputFormatter.display(goalAmount, maxFractionDigits: 0)
                }
            }
            .onChange(of: goalAmountDisplayText) { _, newValue in
                handleGoalAmountDisplayChange(newValue)
            }
        }
    }

    private func handleGoalAmountDisplayChange(_ newValue: String) {
        let sanitized = AmountInputFormatter.sanitize(newValue, maxFractionDigits: 0)
        let formatted = AmountInputFormatter.display(sanitized, maxFractionDigits: 0)
        if newValue != formatted {
            goalAmountDisplayText = formatted
        }
        goalAmount = sanitized
    }

    private func saveGoalSettings() {
        viewModel.handle(.setSavingsGoalEnabled(isEnabled))
        if let amount = AmountInputFormatter.parse(goalAmount) {
            viewModel.handle(.setSavingsGoalAmount(amount))
        }
        dismiss()
    }
    
    private func formatAmount(_ amount: Double, isHidden: Bool = false) -> String {
        if isHidden {
            let digits = Int(amount.rounded())
            let digitCount = String(digits).count
            return String(repeating: "•", count: max(3, digitCount))
        }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: amount)) ?? "0"
    }
}
