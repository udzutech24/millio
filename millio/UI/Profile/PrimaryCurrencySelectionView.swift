//
//  PrimaryCurrencySelectionView.swift
//  millio
//
//  Created by Александр Сидоркин on 21.02.2026.
//

import SwiftUI

struct PrimaryCurrencySelectionView: View {
    @Binding var primaryCurrencyCode: String
    @State private var searchText = ""
    @State private var favoriteCurrencyCodes: [String] = SettingsManager.shared.favoriteCurrencyCodes

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
                    primaryCurrencyCode = code
                }
            )
        }
        .navigationTitle("Валюта")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .onAppear {
            favoriteCurrencyCodes = SettingsManager.shared.favoriteCurrencyCodes
        }
    }

    private func toggleFavorite(_ code: String) {
        let normalized = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }

        if let idx = favoriteCurrencyCodes.firstIndex(where: { $0.uppercased() == normalized }) {
            favoriteCurrencyCodes.remove(at: idx)
        } else {
            favoriteCurrencyCodes.insert(normalized, at: 0)
        }

        favoriteCurrencyCodes = SettingsManager.normalizeCurrencyCodes(favoriteCurrencyCodes)
        SettingsManager.shared.favoriteCurrencyCodes = favoriteCurrencyCodes
    }
}

#Preview {
    NavigationStack {
        PrimaryCurrencySelectionView(primaryCurrencyCode: .constant("RUB"))
    }
}
