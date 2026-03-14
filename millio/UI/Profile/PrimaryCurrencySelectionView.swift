//
//  PrimaryCurrencySelectionView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct PrimaryCurrencySelectionView: View {
    @Environment(AppState.self) private var appState
    @Binding var primaryCurrencyCode: String
    @State private var searchText = ""
    @State private var favoriteCurrencyCodes: [String] = SettingsManager.shared.favoriteCurrencyCodes
    @State private var pendingPrimaryCurrencyCode: String?
    @State private var showPrimaryCurrencyConfirmation = false

    var body: some View {
        ZStack {
            GradientBackground()

            CurrencyPickerView(
                allCodes: CurrencySelectionSupport.allCurrencyCodesForPicker,
                searchText: $searchText,
                selectedCodes: favoriteCurrencyCodes,
                favoriteCodes: Set(favoriteCurrencyCodes),
                currentSelection: primaryCurrencyCode,
                primaryPinnedCode: primaryCurrencyCode,
                onToggleFavorite: toggleFavorite,
                onSelect: { code in
                    requestPrimaryCurrencyChange(code)
                }
            )
        }
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            favoriteCurrencyCodes = SettingsManager.shared.favoriteCurrencyCodes
        }
        .onChange(of: primaryCurrencyCode) { _, _ in
            favoriteCurrencyCodes = SettingsManager.shared.favoriteCurrencyCodes
        }
        .primaryCurrencyConfirmationAlert(
            isPresented: $showPrimaryCurrencyConfirmation,
            content: primaryCurrencyConfirmationContent,
            onConfirm: applyPendingPrimaryCurrencyChange,
            onCancel: resetPendingPrimaryCurrencyChange
        )
    }

    private func requestPrimaryCurrencyChange(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        guard normalized != primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return
        }
        pendingPrimaryCurrencyCode = normalized
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showPrimaryCurrencyConfirmation = true
        }
    }

    private func toggleFavorite(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }
        guard normalized != primaryCurrencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() else {
            return
        }

        if let idx = favoriteCurrencyCodes.firstIndex(where: { $0.uppercased() == normalized }) {
            favoriteCurrencyCodes.remove(at: idx)
        } else {
            favoriteCurrencyCodes.insert(normalized, at: 0)
            // После добавления очищаем поиск, чтобы можно было сразу добрать следующую валюту.
            searchText = ""
        }
        favoriteCurrencyCodes = SettingsManager.normalizeFavoriteCurrencyCodes(
            favoriteCurrencyCodes,
            primaryCode: primaryCurrencyCode
        )
        SettingsManager.shared.favoriteCurrencyCodes = favoriteCurrencyCodes
    }

    private var primaryCurrencyConfirmationContent: PrimaryCurrencyConfirmationContent? {
        guard let pendingPrimaryCurrencyCode else { return nil }
        return PrimaryCurrencyConfirmationContent(
            locale: appState.selectedLanguage.locale ?? Locale.current,
            pendingCode: pendingPrimaryCurrencyCode
        )
    }

    private func applyPendingPrimaryCurrencyChange() {
        guard let pendingPrimaryCurrencyCode else { return }
        primaryCurrencyCode = pendingPrimaryCurrencyCode
        resetPendingPrimaryCurrencyChange()
    }

    private func resetPendingPrimaryCurrencyChange() {
        pendingPrimaryCurrencyCode = nil
    }
}

#Preview {
    NavigationStack {
        PrimaryCurrencySelectionView(primaryCurrencyCode: .constant("RUB"))
    }
}
