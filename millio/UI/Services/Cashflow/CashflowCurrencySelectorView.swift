//
//  CashflowCurrencySelectorView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct CashflowCurrencySelectorView: View {
    @ObservedObject var viewModel: CashflowViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cashflow_display_currency_hint_seen") private var hasSeenDisplayCurrencyHint: Bool = false
    @State private var searchText: String = ""
    @State private var showInfoBanner: Bool = false
    @State private var showInfoAlert: Bool = false
    
    // Используем полный список валют
    private let allCurrencies = CurrencySelectionSupport.allCodes(includeCrypto: true)
    
    var body: some View {
        let favoriteCodes = SettingsManager.shared.favoriteCurrencyCodes
        NavigationStack {
            CurrencyPickerView(
                allCodes: allCurrencies,
                searchText: $searchText,
                selectedCodes: favoriteCodes,
                favoriteCodes: Set(favoriteCodes),
                currentSelection: viewModel.state.displayCurrency,
                primaryPinnedCode: SettingsManager.shared.primaryCurrencyCode,
                onToggleFavorite: nil,
                onSelect: { currency in
                    viewModel.handle(.setDisplayCurrency(currency))
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
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
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
                    .accessibilityLabel("Подсказка о валюте отображения")
                }
            }
            .onAppear {
                if !hasSeenDisplayCurrencyHint {
                    showInfoBanner = true
                    hasSeenDisplayCurrencyHint = true
                }
            }
            .alert("Подсказка", isPresented: $showInfoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(infoMessage)
            }
        }
    }

    private var infoMessage: String {
        "Основная валюта меняется только в Профиле. Здесь валюта влияет только на просмотр и сбрасывается после выхода из Кэшфлоу."
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
            .accessibilityLabel("Скрыть уведомление")
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
