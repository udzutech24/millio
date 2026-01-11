//
//  FinanceDynamicsDetailsView.swift
//  millio
//
//  Created by Александр Сидоркин on 13.01.2026.
//

import SwiftUI

struct FinanceDynamicsDetailsView: View {
    @ObservedObject var viewModel: FinanceDynamicsViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if viewModel.state.chartData.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("Нет данных")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(viewModel.state.chartData) { dataPoint in
                                HStack {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(
                                            LinearGradient(
                                                colors: AppColors.financesGradient,
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .frame(width: 16, height: 16)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(dataPoint.label)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Text(formatDate(dataPoint.date))
                                            .font(.system(size: 12, weight: .regular))
                                            .foregroundStyle(AppColors.textTertiary)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(formatAmount(dataPoint.value))
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(AppColors.textPrimary)
                                        
                                        Text(viewModel.state.displayCurrency)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(AppColors.textSecondary)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.white.opacity(0.05))
                                )
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("Детали")
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
    
    private func formatAmount(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: amount)) ?? "0.00"
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        switch viewModel.state.period {
        case .day:
            formatter.dateFormat = "HH:mm"
        case .week:
            formatter.dateFormat = "dd.MM"
        case .month:
            formatter.dateFormat = "dd.MM"
        case .year:
            formatter.dateFormat = "MMM"
        }
        return formatter.string(from: date)
    }
}
