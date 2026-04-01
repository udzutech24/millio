//
//  CashflowCurrencySelectorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct CashflowCurrencySelectorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(AppState.self) private var appState
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cashflow_display_currency_hint_seen") private var hasSeenDisplayCurrencyHint: Bool = false
    @State private var searchText: String = ""
    @State private var showInfoBanner: Bool = false
    @State private var showInfoAlert: Bool = false
    @State private var showCryptoProAlert: Bool = false

    private var locale: Locale { AppLocalization.currentAppLocale }
    
    // Используем полный список валют
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
                currentSelection: viewModel.state.displayCurrency,
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
                    viewModel.handle(.setDisplayCurrency(currency))
                    dismiss()
                }
            )
            .premiumUpsellAlert(
                isPresented: $showCryptoProAlert,
                titleKey: "monetization.crypto.pro_title",
                message: .key("monetization.crypto.pro_message"),
                onSubscribe: { router.push(.subscription) }
            )
            .safeAreaInset(edge: .top) {
                if showInfoBanner {
                    infoBanner(message: infoMessage)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }
            }
            .navigationTitle(localized("cashflow.display_currency.title", fallback: "Display currency"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("cashflow.common.cancel", fallback: "Cancel")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showInfoAlert = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .accessibilityLabel(localized("cashflow.display_currency.hint_accessibility", fallback: "Display currency hint"))
                }
            }
            .onAppear {
                if !hasSeenDisplayCurrencyHint {
                    showInfoBanner = true
                    hasSeenDisplayCurrencyHint = true
                }
            }
            .alert(localized("cashflow.display_currency.hint_title", fallback: "Hint"), isPresented: $showInfoAlert) {
                Button(localized("cashflow.common.ok", fallback: "OK"), role: .cancel) {}
            } message: {
                Text(infoMessage)
            }
        }
    }

    private var infoMessage: String {
        localized(
            "cashflow.display_currency.hint_message",
            fallback: "Primary currency can only be changed in Profile. Here, currency affects only the view and resets after leaving Cashflow."
        )
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
            .accessibilityLabel(localized("cashflow.display_currency.hide_hint_accessibility", fallback: "Hide notification"))
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

    private func localized(_ key: String, fallback: String) -> String {
        AppLocalization.string(key, locale: locale, fallback: fallback)
    }
}
