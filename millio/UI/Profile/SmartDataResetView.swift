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
        .navigationTitle("Smart reset")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert(
            "Confirm reset",
            isPresented: $showConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete selected data", role: .destructive) {
                applyReset()
            }
        } message: {
            Text("This action cannot be undone. Creating a backup first is recommended.")
        }
        .alert("Reset complete", isPresented: Binding(
            get: { successMessage != nil },
            set: { newValue in
                if !newValue { successMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .alert("Failed to reset data", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
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
                Text("Important")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Period is applied to operations, account operations, balance zeroing, and cashback. It is not used when deleting accounts, categories, or settings.")
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
            FinancesSectionHeader(title: "Period")
            FinancesGlassCard {
                VStack(spacing: 12) {
                    Picker("Period", selection: $periodPreset) {
                        ForEach(DataResetPeriodPreset.allCases) { preset in
                            Text(preset.title).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)

                    if periodPreset == .custom {
                        DatePicker(
                            "From",
                            selection: $customStartDate,
                            displayedComponents: .date
                        )
                        .tint(AppColors.textPrimary)

                        DatePicker(
                            "To",
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
            FinancesSectionHeader(title: "What to delete")
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle("Full reset (all data types)", isOn: $isFullReset)
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
            FinancesSectionHeader(title: "Preview")
            FinancesGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    estimateRow("Operations", value: estimate.deletedTransactions)
                    estimateRow("Cashback", value: estimate.deletedCashbacks)
                    estimateRow("Cards", value: estimate.deletedCards)
                    estimateRow("Credits", value: estimate.deletedCredits)
                    estimateRow("Investments", value: estimate.deletedInvestments)
                    estimateRow("Account links", value: estimate.deletedFinanceAccounts)
                    estimateRow("Account groups", value: estimate.deletedFinanceGroups)
                    estimateRow("Custom cashflow categories", value: estimate.deletedCashflowCustomCategories)
                    estimateRow("System category overrides", value: estimate.deletedCashflowSystemOverrides)
                    estimateRow("Custom cashback categories", value: estimate.deletedCashbackCustomCategories)
                    estimateRow("Zeroed cards", value: estimate.zeroedCards)
                    estimateRow("Zeroed credits", value: estimate.zeroedCredits)
                    estimateRow("Zeroed investments", value: estimate.zeroedInvestments)
                    estimateRow("Created adjustments", value: estimate.createdAdjustmentTransactions)
                    estimateRow("Settings reset", value: estimate.settingsReset ? 1 : 0)

                    FinancesRowDivider()
                        .padding(.vertical, 4)

                    HStack {
                        Text("Total changes")
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
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.brandPrimary)

                    Text("Recommended: create a backup before applying reset.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash.fill")
                        Text(isApplying ? "Resetting..." : "Apply reset")
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
            successMessage = "Applied changes: \(result.totalChanges)"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
