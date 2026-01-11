//
//  CashbackView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import SwiftData

struct CashbackView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: CashbackViewModel?
    
    var body: some View {
        Group {
            if let viewModel = viewModel {
                CashbackContentViewInternal(viewModel: viewModel)
            } else {
                ProgressView()
                    .tint(AppColors.textPrimary)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = CashbackViewModel(modelContext: modelContext)
            }
        }
    }
}

// MARK: - Content View

private struct CashbackContentViewInternal: View {
    @ObservedObject var viewModel: CashbackViewModel
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Выбранная карта
                    selectedCardSection
                    
                    // Заглушка для будущего функционала
                    placeholderSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("Кешбэк")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { viewModel.state.showCardPicker },
            set: { if !$0 { viewModel.handle(.hideCardPicker) } }
        )) {
            CardPickerView(viewModel: viewModel)
        }
    }
    
    // MARK: - Selected Card Section
    
    private var selectedCardSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Привязанная карта")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                
                Spacer()
            }
            
            if let card = viewModel.state.selectedCard {
                // Карточка выбранной карты
                Button {
                    viewModel.handle(.showCardPicker)
                } label: {
                    HStack(spacing: 16) {
                        // Иконка карты
                        Image(systemName: card.cardType.icon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 56, height: 56)
                            .background {
                                Circle()
                                    .fill(.ultraThinMaterial)
                            }
                        
                        // Информация о карте
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.name)
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            
                            Text(card.bank.displayName)
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(AppColors.textSecondary)
                            
                            Text(card.maskedNumber)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(AppColors.textTertiary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: AppColors.cashbackGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Кнопка выбора карты
                Button {
                    viewModel.handle(.showCardPicker)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: AppColors.cashbackGradient,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                        
                        Text("Выбрать карту")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(20)
                    .background {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.ultraThinMaterial)
                            .overlay {
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(
                                        LinearGradient(
                                            colors: AppColors.cashbackGradient,
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: 1.5
                                    )
                            }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Placeholder Section
    
    private var placeholderSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "percent")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: AppColors.cashbackGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Text("Кешбэк")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            
            Text("Функционал кешбэка будет доступен в следующих версиях")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
    }
}

// MARK: - Card Picker View

private struct CardPickerView: View {
    @ObservedObject var viewModel: CashbackViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                
                if viewModel.state.availableCards.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "creditcard.trianglebadge.exclamationmark")
                            .font(.system(size: 64))
                            .foregroundStyle(AppColors.textTertiary)
                        
                        Text("Нет доступных карт")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        
                        Text("Добавьте карту в сервисе \"Картотека\"")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(AppColors.textTertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            // Опция "Не привязывать"
                            Button {
                                viewModel.handle(.selectCard(nil))
                                dismiss()
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 24, weight: .semibold))
                                        .foregroundStyle(AppColors.textTertiary)
                                    
                                    Text("Не привязывать карту")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(AppColors.textPrimary)
                                    
                                    Spacer()
                                    
                                    if viewModel.state.selectedCard == nil {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .leading,
                                                    endPoint: .trailing
                                                )
                                            )
                                    }
                                }
                                .padding(16)
                                .background {
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(.ultraThinMaterial)
                                        .overlay {
                                            if viewModel.state.selectedCard == nil {
                                                RoundedRectangle(cornerRadius: 16)
                                                    .stroke(
                                                        LinearGradient(
                                                            colors: AppColors.cashbackGradient,
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        ),
                                                        lineWidth: 1.5
                                                    )
                                            }
                                        }
                                }
                            }
                            .buttonStyle(.plain)
                            
                            // Список карт
                            ForEach(viewModel.state.availableCards) { card in
                                Button {
                                    viewModel.handle(.selectCard(card))
                                    dismiss()
                                } label: {
                                    HStack(spacing: 16) {
                                        // Иконка карты
                                        Image(systemName: card.cardType.icon)
                                            .font(.system(size: 28, weight: .semibold))
                                            .foregroundStyle(
                                                LinearGradient(
                                                    colors: AppColors.cashbackGradient,
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                            .frame(width: 48, height: 48)
                                            .background {
                                                Circle()
                                                    .fill(.ultraThinMaterial)
                                            }
                                        
                                        // Информация о карте
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Text(card.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundStyle(AppColors.textPrimary)
                                                
                                                if card.isFavorite {
                                                    Image(systemName: "star.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundStyle(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            )
                                                        )
                                                }
                                            }
                                            
                                            Text(card.bank.displayName)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(AppColors.textSecondary)
                                            
                                            Text(card.maskedNumber)
                                                .font(.system(size: 13, weight: .regular))
                                                .foregroundStyle(AppColors.textTertiary)
                                        }
                                        
                                        Spacer()
                                        
                                        if viewModel.state.selectedCard?.persistentModelID == card.persistentModelID {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(
                                                    LinearGradient(
                                                        colors: AppColors.cashbackGradient,
                                                        startPoint: .leading,
                                                        endPoint: .trailing
                                                    )
                                                )
                                        }
                                    }
                                    .padding(16)
                                    .background {
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(.ultraThinMaterial)
                                            .overlay {
                                                if viewModel.state.selectedCard?.persistentModelID == card.persistentModelID {
                                                    RoundedRectangle(cornerRadius: 16)
                                                        .stroke(
                                                            LinearGradient(
                                                                colors: AppColors.cashbackGradient,
                                                                startPoint: .leading,
                                                                endPoint: .trailing
                                                            ),
                                                            lineWidth: 1.5
                                                        )
                                                }
                                            }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle("Выбор карты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                    .foregroundStyle(
                        LinearGradient(
                            colors: AppColors.cashbackGradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        CashbackView()
    }
}
