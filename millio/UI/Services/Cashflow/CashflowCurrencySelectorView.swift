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
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if viewModel.state.availableCurrencies.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .tint(AppColors.textPrimary)
                        Text("Загрузка валют...")
                            .font(.system(size: 16))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(viewModel.state.availableCurrencies, id: \.self) { currency in
                                Button {
                                    viewModel.handle(.setDisplayCurrency(currency))
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(currency)
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Spacer()
                                        
                                        if currency == viewModel.state.displayCurrency {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: AppColors.cashflowGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 16)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .fill(Color.black.opacity(0.3))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Валюта отображения")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}
