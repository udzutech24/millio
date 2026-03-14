//
//  BudgetSetupSheet.swift
//  millio
//
//  Created by Codex on 14.03.2026.
//

import SwiftUI

struct BudgetSetupSheet: View {
    let periodTitle: String
    let currencyCode: String
    let existingAmount: Double?
    let categoryOptions: [CashflowCategoryOption]
    let existingCategoryLimits: [String: Double]
    let categorySnapshots: [BudgetCategoryProgressSnapshot]
    let onSave: (Double, [String: Double]) -> Void
    let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var rawAmount: String = ""
    @State private var categoryDrafts: [String: String]

    init(
        periodTitle: String,
        currencyCode: String,
        existingAmount: Double?,
        categoryOptions: [CashflowCategoryOption],
        existingCategoryLimits: [String: Double],
        categorySnapshots: [BudgetCategoryProgressSnapshot],
        onSave: @escaping (Double, [String: Double]) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.periodTitle = periodTitle
        self.currencyCode = currencyCode
        self.existingAmount = existingAmount
        self.categoryOptions = categoryOptions
        self.existingCategoryLimits = existingCategoryLimits
        self.categorySnapshots = categorySnapshots
        self.onSave = onSave
        self.onDelete = onDelete
        _rawAmount = State(initialValue: existingAmount.map(AmountInputFormatter.plainString(from:)) ?? "")
        _categoryDrafts = State(
            initialValue: existingCategoryLimits.mapValues { AmountInputFormatter.plainString(from: $0) }
        )
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerSection
                        totalLimitSection
                        categoryLimitsSection
                        footerHint
                    }
                    .padding(20)
                    .padding(.bottom, 120)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomActions
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .background(Color.black.opacity(0.92))
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(budgetLocalized(ru: "Готово", en: "Done")) {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }

    private var parsedTotal: Double {
        AmountInputFormatter.parse(rawAmount) ?? 0
    }

    private var parsedCategoryLimits: [String: Double] {
        categoryDrafts.reduce(into: [String: Double]()) { result, pair in
            guard let value = AmountInputFormatter.parse(pair.value), value > 0 else { return }
            result[pair.key] = value
        }
    }

    private var categoryLimitSum: Double {
        parsedCategoryLimits.values.reduce(0, +)
    }

    private var hasOverflowConflict: Bool {
        parsedTotal > 0 && categoryLimitSum - parsedTotal > 0.0000001
    }

    private var canSave: Bool {
        parsedTotal > 0 && !hasOverflowConflict
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(budgetLocalized(ru: "Лимит бюджета", en: "Budget limit"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)
            Text(periodTitle)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
        }
    }

    private var totalLimitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(budgetLocalized(ru: "Общий лимит", en: "Total limit"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            HStack(spacing: 10) {
                TextField(
                    "0",
                    text: Binding(
                        get: { AmountInputFormatter.display(rawAmount, maxFractionDigits: 0) },
                        set: { rawAmount = AmountInputFormatter.sanitize($0, maxFractionDigits: 0) }
                    )
                )
                .keyboardType(.decimalPad)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

                Text(currencyCode)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.72))
            }
            .padding(16)
            .background(cardBackground(stroke: Color.white.opacity(0.16)))

            HStack {
                Text(
                    budgetLocalized(
                        ru: "Сумма лимитов категорий",
                        en: "Category limits total"
                    )
                )
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.72))
                Spacer()
                Text("\(cashflowAmountText(categoryLimitSum)) \(currencyCode)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(hasOverflowConflict ? Color.red.opacity(0.95) : AppColors.textPrimary)
            }

            if hasOverflowConflict {
                Text(
                    budgetLocalized(
                        ru: "Категорийные лимиты превышают общий на \(cashflowAmountText(categoryLimitSum - parsedTotal)) \(currencyCode). Это плохая конфигурация, её нельзя сохранять.",
                        en: "Category limits exceed the total by \(cashflowAmountText(categoryLimitSum - parsedTotal)) \(currencyCode). This configuration is invalid and cannot be saved."
                    )
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.92))
            }
        }
    }

    private var categoryLimitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(budgetLocalized(ru: "Лимиты по категориям", en: "Category limits"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(
                        budgetLocalized(
                            ru: "Задай индивидуальные ограничения только там, где реально нужен контроль.",
                            en: "Set individual caps only for categories that actually need control."
                        )
                    )
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.68))
                }
                Spacer()
                Button {
                    categoryDrafts = [:]
                } label: {
                    Text(budgetLocalized(ru: "Сбросить", en: "Reset"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(cardBackground(stroke: Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                ForEach(categoryOptions) { option in
                    BudgetCategoryLimitDraftRow(
                        option: option,
                        currencyCode: currencyCode,
                        rawValue: Binding(
                            get: { categoryDrafts[option.rawValue] ?? "" },
                            set: { categoryDrafts[option.rawValue] = AmountInputFormatter.sanitize($0, maxFractionDigits: 0) }
                        ),
                        snapshot: categorySnapshots.first(where: { $0.categoryRawValue == option.rawValue }),
                        onClear: {
                            categoryDrafts[option.rawValue] = ""
                        }
                    )
                }
            }
        }
    }

    private var footerHint: some View {
        Text(
            budgetLocalized(
                ru: "Главный лимит должен оставаться главным. Категории нужны не для красоты, а чтобы быстро ловить перерасход в узких местах.",
                en: "The total limit should stay primary. Category limits exist to catch focused overspending, not to create visual noise."
            )
        )
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(Color.white.opacity(0.62))
    }

    private var bottomActions: some View {
        VStack(spacing: 10) {
            Button {
                onSave(parsedTotal, parsedCategoryLimits)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } label: {
                Text(budgetLocalized(ru: "Сохранить лимиты", en: "Save limits"))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .opacity(canSave ? 1 : 0.45)

            if let onDelete, existingAmount != nil {
                Button {
                    onDelete()
                    dismiss()
                } label: {
                    Text(budgetLocalized(ru: "Удалить лимит", en: "Delete limit"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.95))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cardBackground(stroke: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(Color.white.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

private struct BudgetCategoryLimitDraftRow: View {
    let option: CashflowCategoryOption
    let currencyCode: String
    @Binding var rawValue: String
    let snapshot: BudgetCategoryProgressSnapshot?
    let onClear: () -> Void

    private var parsedValue: Double {
        AmountInputFormatter.parse(rawValue) ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(option.icon)
                    .font(.system(size: 22))
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.displayName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    if let snapshot {
                        Text(statusSubtitle(snapshot))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(statusColor(snapshot.status))
                    } else {
                        Text(budgetLocalized(ru: "Лимит не задан", en: "No limit set"))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.56))
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    TextField(
                        "0",
                        text: Binding(
                            get: { AmountInputFormatter.display(rawValue, maxFractionDigits: 0) },
                            set: { rawValue = AmountInputFormatter.sanitize($0, maxFractionDigits: 0) }
                        )
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 84)

                    Text(currencyCode)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.68))

                    if parsedValue > 0 {
                        Button {
                            onClear()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.58))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let snapshot, snapshot.limit > 0 {
                GeometryReader { proxy in
                    let progress = min(max(snapshot.progress, 0), 1)
                    ZStack(alignment: .leading) {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.07))
                        Capsule(style: .continuous)
                            .fill(statusColor(snapshot.status))
                            .frame(width: max(10, proxy.size.width * progress))
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    private func statusSubtitle(_ snapshot: BudgetCategoryProgressSnapshot) -> String {
        let spent = cashflowAmountText(snapshot.spent)
        let limit = cashflowAmountText(snapshot.limit)
        switch snapshot.status {
        case .normal:
            return budgetLocalized(ru: "\(spent) из \(limit)", en: "\(spent) of \(limit)")
        case .warning:
            return budgetLocalized(ru: "\(spent) из \(limit) · близко к лимиту", en: "\(spent) of \(limit) · getting close")
        case .critical:
            return budgetLocalized(ru: "\(spent) из \(limit) · почти предел", en: "\(spent) of \(limit) · near limit")
        case .exceeded:
            return budgetLocalized(ru: "Перерасход \(cashflowAmountText(abs(snapshot.remaining)))", en: "Over by \(cashflowAmountText(abs(snapshot.remaining)))")
        }
    }

    private func statusColor(_ status: BudgetStatus) -> Color {
        switch status {
        case .normal:
            return Color(hex: "6DFFC7")
        case .warning:
            return Color(hex: "FFD66D")
        case .critical:
            return Color(hex: "FF9B6A")
        case .exceeded:
            return Color(hex: "FF6666")
        }
    }
}
