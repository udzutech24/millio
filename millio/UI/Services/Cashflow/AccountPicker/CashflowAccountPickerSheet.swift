//
//  CashflowAccountPickerSheet.swift
//  millio
//

import SwiftUI

/// Какой селектор счёта формы транзакции сейчас открыт в шите.
enum CashflowAccountPickerTarget: String, Identifiable {
    case main
    case transferFrom
    case transferTo

    var id: String { rawValue }
}

/// Разбиение списка счетов на секции пикера. Порядок внутри секций — исходный,
/// чтобы сортировка резолвера (и, как следствие, дефолтный счёт формы) не менялась.
enum CashflowAccountPickerSections {
    static func split(
        _ accounts: [CashflowSelectableAccount]
    ) -> (favorites: [CashflowSelectableAccount], others: [CashflowSelectableAccount]) {
        (accounts.filter(\.isFavorite), accounts.filter { !$0.isFavorite })
    }
}

/// Bottom sheet выбора счёта в формах Cashflow: секция «Избранные» сверху, ниже остальные счета.
/// Строка = иконка + название + «доступно к трате». Единый компонент для расхода/дохода и
/// для обоих селекторов перевода.
struct CashflowAccountPickerSheet: View {
    let title: String
    let accounts: [CashflowSelectableAccount]
    /// `id` выбранного счёта (`CashflowSelectableAccount.id`), не `cardID`.
    let selectedID: String?
    /// Детали строк считаются вне `body`: баланс core-счёта — реплей событий, а счетов может
    /// быть много, поэтому синхронный расчёт при отрисовке подвесил бы шит.
    let loadDetails: ([CashflowSelectableAccount]) async -> [String: CashflowAccountPickerDetails]
    let onSelect: (CashflowSelectableAccount) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var details: [String: CashflowAccountPickerDetails] = [:]
    @State private var isLoadingDetails = true

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        let sections = CashflowAccountPickerSections.split(accounts)

                        if !sections.favorites.isEmpty {
                            sectionHeader(L("cashflow.account_picker.favorites"))
                            rows(for: sections.favorites)
                        }

                        if !sections.others.isEmpty {
                            sectionHeader(
                                sections.favorites.isEmpty
                                    ? L("cashflow.account_picker.all_accounts")
                                    : L("cashflow.account_picker.other_accounts")
                            )
                            rows(for: sections.others)
                        }
                    }
                    .padding(.horizontal, AppSpacing.l)
                    .padding(.bottom, AppSpacing.xxl)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            details = await loadDetails(accounts)
            isLoadingDetails = false
        }
    }

    private var header: some View {
        HStack {
            Text(title)
                .font(.millioHeadline)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(L("common.close")) { dismiss() }
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.l)
    }

    @ViewBuilder
    private func rows(for accounts: [CashflowSelectableAccount]) -> some View {
        ForEach(accounts) { account in
            Button {
                onSelect(account)
                dismiss()
            } label: {
                CashflowAccountPickerRow(
                    account: account,
                    details: details[account.id],
                    isLoadingDetails: isLoadingDetails,
                    isSelected: account.id == selectedID
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.millioCaption)
            .foregroundStyle(AppColors.textTertiary)
            .textCase(.uppercase)
            .padding(.top, AppSpacing.m)
            .padding(.bottom, AppSpacing.xs)
    }
}

/// Строка счёта в пикере. Повторяет раскладку `NewCoreAccountRow` с экрана «Счета»
/// (иконка + название + сумма) на том же `AccountIconBadgeView`, но работает на
/// презентационном DTO, а не на конкретной SwiftData-модели.
struct CashflowAccountPickerRow: View {
    let account: CashflowSelectableAccount
    let details: CashflowAccountPickerDetails?
    let isLoadingDetails: Bool
    let isSelected: Bool

    private var amountValue: Double? {
        details?.availableAmount.map { NSDecimalNumber(decimal: $0).doubleValue }
    }

    private var amountColor: Color {
        (amountValue ?? 0) < 0 ? AppColors.error : AppColors.textPrimary
    }

    private var currencySymbol: String {
        MonetaCurrency(rawValue: account.currency)?.symbol ?? account.currency
    }

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            AccountIconBadgeView(
                iconName: details?.iconName,
                iconColor: details?.iconColorHex,
                fallback: details?.fallbackIconName ?? "creditcard.fill",
                size: 36,
                isError: (amountValue ?? 0) < 0
            )

            Text(account.title)
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            amountView

            Image(systemName: "checkmark")
                .font(.millioCaption)
                .foregroundStyle(AppColors.textPrimary)
                .opacity(isSelected ? 1 : 0)
        }
        .padding(.vertical, AppSpacing.s)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var amountView: some View {
        if let amountValue {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(Self.formattedAmount(amountValue))
                    .font(.millioSubheadline)
                    .foregroundStyle(amountColor.opacity(0.92))
                Text(currencySymbol)
                    .font(.millioCallout)
                    .foregroundStyle(amountColor.opacity(0.66))
            }
        } else if isLoadingDetails {
            // Скелетон, пока балансы считаются: показывать «0 ₽» до загрузки нельзя —
            // это ровно тот класс багов, где кэш-срез выдаётся за живые данные.
            RoundedRectangle(cornerRadius: AppSpacing.xs, style: .continuous)
                .fill(AppColors.textTertiary.opacity(0.18))
                .frame(width: 56, height: 12)
        } else {
            Text("—")
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textTertiary)
        }
    }

    static func formattedAmount(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
