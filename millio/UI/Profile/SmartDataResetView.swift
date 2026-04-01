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

    private var locale: Locale {
        AppLocalization.currentAppLocale
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
        .navigationTitle(SmartDataResetL10n.navigationTitle(locale: locale))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .alert(
            SmartDataResetL10n.confirmResetTitle(locale: locale),
            isPresented: $showConfirmation
        ) {
            Button(SmartDataResetL10n.cancel(locale: locale), role: .cancel) {}
            Button(SmartDataResetL10n.deleteSelectedData(locale: locale), role: .destructive) {
                applyReset()
            }
        } message: {
            Text(SmartDataResetL10n.confirmResetMessage(locale: locale))
        }
        .alert(SmartDataResetL10n.resetCompleteTitle(locale: locale), isPresented: Binding(
            get: { successMessage != nil },
            set: { newValue in
                if !newValue { successMessage = nil }
            }
        )) {
            Button(SmartDataResetL10n.ok(locale: locale), role: .cancel) {}
        } message: {
            Text(successMessage ?? "")
        }
        .alert(SmartDataResetL10n.failedResetTitle(locale: locale), isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button(SmartDataResetL10n.ok(locale: locale), role: .cancel) {}
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
                Text(SmartDataResetL10n.warningTitle(locale: locale))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text(SmartDataResetL10n.warningBody(locale: locale))
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
            FinancesSectionHeader(title: SmartDataResetL10n.periodSectionTitle(locale: locale))
            FinancesGlassCard {
                VStack(spacing: 12) {
                    Picker(SmartDataResetL10n.periodPickerTitle(locale: locale), selection: $periodPreset) {
                        ForEach(DataResetPeriodPreset.allCases) { preset in
                            Text(SmartDataResetL10n.periodTitle(preset, locale: locale)).tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(AppColors.textPrimary)

                    if periodPreset == .custom {
                        DatePicker(
                            SmartDataResetL10n.periodFrom(locale: locale),
                            selection: $customStartDate,
                            displayedComponents: .date
                        )
                        .tint(AppColors.textPrimary)

                        DatePicker(
                            SmartDataResetL10n.periodTo(locale: locale),
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
            FinancesSectionHeader(title: SmartDataResetL10n.targetsSectionTitle(locale: locale))
            FinancesGlassCard {
                VStack(spacing: 0) {
                    Toggle(SmartDataResetL10n.fullResetTitle(locale: locale), isOn: $isFullReset)
                        .foregroundStyle(AppColors.textPrimary)
                        .tint(AppColors.toggleOnGreen)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                    if !isFullReset {
                        ForEach(DataResetTarget.allCases) { target in
                            FinancesRowDivider()
                            Toggle(
                                SmartDataResetL10n.targetTitle(target, locale: locale),
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
            FinancesSectionHeader(title: SmartDataResetL10n.previewSectionTitle(locale: locale))
            FinancesGlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    estimateRow(SmartDataResetL10n.estimateLabelTransactions(locale: locale), value: estimate.deletedTransactions)
                    estimateRow(SmartDataResetL10n.estimateLabelCashback(locale: locale), value: estimate.deletedCashbacks)
                    estimateRow(SmartDataResetL10n.estimateLabelCards(locale: locale), value: estimate.deletedCards)
                    estimateRow(SmartDataResetL10n.estimateLabelCredits(locale: locale), value: estimate.deletedCredits)
                    estimateRow(SmartDataResetL10n.estimateLabelInvestments(locale: locale), value: estimate.deletedInvestments)
                    estimateRow(SmartDataResetL10n.estimateLabelAccountLinks(locale: locale), value: estimate.deletedFinanceAccounts)
                    estimateRow(SmartDataResetL10n.estimateLabelAccountGroups(locale: locale), value: estimate.deletedFinanceGroups)
                    estimateRow(SmartDataResetL10n.estimateLabelCashflowCustomCategories(locale: locale), value: estimate.deletedCashflowCustomCategories)
                    estimateRow(SmartDataResetL10n.estimateLabelCashflowSystemOverrides(locale: locale), value: estimate.deletedCashflowSystemOverrides)
                    estimateRow(SmartDataResetL10n.estimateLabelCashbackCustomCategories(locale: locale), value: estimate.deletedCashbackCustomCategories)
                    estimateRow(SmartDataResetL10n.estimateLabelZeroedCards(locale: locale), value: estimate.zeroedCards)
                    estimateRow(SmartDataResetL10n.estimateLabelZeroedCredits(locale: locale), value: estimate.zeroedCredits)
                    estimateRow(SmartDataResetL10n.estimateLabelZeroedInvestments(locale: locale), value: estimate.zeroedInvestments)
                    estimateRow(SmartDataResetL10n.estimateLabelCreatedAdjustments(locale: locale), value: estimate.createdAdjustmentTransactions)
                    estimateRow(SmartDataResetL10n.estimateLabelSettingsReset(locale: locale), value: estimate.settingsReset ? 1 : 0)

                    FinancesRowDivider()
                        .padding(.vertical, 4)

                    HStack {
                        Text(SmartDataResetL10n.totalChangesTitle(locale: locale))
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

                    Text(SmartDataResetL10n.backupRecommendation(locale: locale))
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
                        Text(SmartDataResetL10n.applyResetButton(isApplying: isApplying, locale: locale))
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
            successMessage = SmartDataResetL10n.appliedChangesMessage(result.totalChanges, locale: locale)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
