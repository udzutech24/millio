//
//  SmartDataResetView.swift
//  millio
//
//  Created by Codex on 05.03.2026.
//

import SwiftUI
import SwiftData

struct SmartDataResetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var periodPreset: DataResetPeriodPreset = .allTime
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var isFullReset: Bool = false
    @State private var selectedTargets: Set<DataResetTarget> = [.operations]
    @State private var estimate: DataResetEstimate = .init()
    @State private var errorMessage: String?
    @State private var successMessage: String?
    @State private var showConfirmation: Bool = false
    @State private var isApplying: Bool = false

    private var service: DataResetService {
        DataResetService(modelContext: modelContext, appState: appState)
    }

    private var request: DataResetRequest {
        let targets = isFullReset ? Set(DataResetTarget.allCases) : selectedTargets
        return DataResetRequest(
            period: DataResetPeriod(
                preset: periodPreset,
                customStartDate: customStartDate,
                customEndDate: customEndDate
            ),
            targets: targets
        )
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(spacing: 20) {
                    warningCard
                    periodCard
                    targetsCard
                    estimateCard
                    actionCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .padding(.top, 8)
            }
        }
        .navigationTitle("Умная очистка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Подтвердите очистку",
            isPresented: $showConfirmation,
            titleVisibility: .visible
        ) {
            Button("Удалить выбранные данные", role: .destructive) {
                applyReset()
            }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Операция необратима. Перед очисткой рекомендуется создать backup.")
        }
        .alert("Очистка завершена", isPresented: Binding(
            get: { successMessage != nil },
            set: { newValue in
                if !newValue { successMessage = nil }
            }
        )) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .alert("Не удалось выполнить очистку", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("Ок", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear {
            refreshEstimate()
        }
        .onChange(of: periodPreset) { _, _ in refreshEstimate() }
        .onChange(of: customStartDate) { _, _ in refreshEstimate() }
        .onChange(of: customEndDate) { _, _ in refreshEstimate() }
        .onChange(of: selectedTargets) { _, _ in refreshEstimate() }
        .onChange(of: isFullReset) { _, isOn in
            if isOn {
                selectedTargets = Set(DataResetTarget.allCases)
            } else if selectedTargets.isEmpty {
                selectedTargets = [.operations]
            }
            refreshEstimate()
        }
    }

    private var warningCard: some View {
        FinancesGlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Что важно")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Период применяется к операциям, операциям по счетам, обнулению счетов и кешбэку. Для удаления счетов/категорий/настроек период не используется.")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private var periodCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Период")
            FinancesGlassCard {
                VStack(spacing: 12) {
                    Picker("Период", selection: $periodPreset) {
                        ForEach(DataResetPeriodPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)

                    if periodPreset == .custom {
                        DatePicker(
                            "С",
                            selection: $customStartDate,
                            displayedComponents: .date
                        )
                        .tint(AppColors.textPrimary)

                        DatePicker(
                            "По",
                            selection: $customEndDate,
                            displayedComponents: .date
                        )
                        .tint(AppColors.textPrimary)
                    }
                }
                .padding(16)
            }
        }
    }

    private var targetsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Что удалить")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle("Полный сброс (все типы данных)", isOn: $isFullReset)
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.toggleOnGreen)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    if !isFullReset {
                        ForEach(DataResetTarget.allCases) { target in
                            FinancesRowDivider()
                            Toggle(
                                target.title,
                                isOn: Binding(
                                    get: { selectedTargets.contains(target) },
                                    set: { newValue in
                                        if newValue {
                                            selectedTargets.insert(target)
                                        } else {
                                            selectedTargets.remove(target)
                                        }
                                    }
                                )
                            )
                            .foregroundStyle(AppColors.textPrimary)
                            .tint(AppColors.toggleOnGreen)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
    }

    private var estimateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            FinancesSectionHeader(title: "Предпросмотр")
            FinancesGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    estimateRow("Операции", value: estimate.deletedTransactions)
                    estimateRow("Кешбэк", value: estimate.deletedCashbacks)
                    estimateRow("Карты", value: estimate.deletedCards)
                    estimateRow("Кредиты", value: estimate.deletedCredits)
                    estimateRow("Инвестиции", value: estimate.deletedInvestments)
                    estimateRow("Связи счетов", value: estimate.deletedFinanceAccounts)
                    estimateRow("Группы счетов", value: estimate.deletedFinanceGroups)
                    estimateRow("Кастомные категории cashflow", value: estimate.deletedCashflowCustomCategories)
                    estimateRow("Оверрайды системных категорий", value: estimate.deletedCashflowSystemOverrides)
                    estimateRow("Кастомные категории кешбэка", value: estimate.deletedCashbackCustomCategories)
                    estimateRow("Обнулено карт", value: estimate.zeroedCards)
                    estimateRow("Обнулено кредитов", value: estimate.zeroedCredits)
                    estimateRow("Обнулено инвестиций", value: estimate.zeroedInvestments)
                    estimateRow("Создано корректировок", value: estimate.createdAdjustmentTransactions)
                    estimateRow("Сброс настроек", value: estimate.settingsReset ? 1 : 0)

                    FinancesRowDivider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("Всего изменений")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(estimate.totalChanges)")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .padding(16)
            }
        }
    }

    private var actionCard: some View {
        FinancesGlassCard {
            VStack(spacing: 12) {
                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text(isApplying ? "Очистка..." : "Применить очистку")
                            .font(.system(size: 16, weight: .semibold))
                        if isApplying {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(.white)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppColors.error)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!request.isValid || estimate.totalChanges == 0 || isApplying)
            }
            .padding(16)
        }
    }

    private func estimateRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(AppColors.textTertiary)
            Spacer()
            Text("\(value)")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func refreshEstimate() {
        do {
            estimate = try service.estimate(request)
            errorMessage = nil
        } catch {
            estimate = .init()
            errorMessage = error.localizedDescription
        }
    }

    private func applyReset() {
        isApplying = true
        defer { isApplying = false }

        do {
            let result = try service.execute(request)
            estimate = result
            successMessage = "Изменений применено: \(result.totalChanges)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
