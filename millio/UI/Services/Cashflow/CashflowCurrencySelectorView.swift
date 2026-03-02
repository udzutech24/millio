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
    @State private var searchText: String = ""
    
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
                onToggleFavorite: nil,
                onSelect: { currency in
                    viewModel.handle(.setDisplayCurrency(currency))
                    dismiss()
                }
            )
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}
