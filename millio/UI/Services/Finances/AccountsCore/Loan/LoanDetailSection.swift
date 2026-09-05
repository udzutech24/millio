import SwiftUI

/// Действия деталки кредита.
enum LoanDetailAction: Equatable {
    case payment
    case prepayment
    case schedule
    case terms
}

/// То, что лежит под hero-карточкой кредита (макет, ЭКРАН 1): теги условий, кнопки действий и
/// разбивка ближайшего платежа. Цифры приходят готовыми — секция ничего не считает.
struct LoanDetailSection: View {
    let presentation: LoanDetailPresentation
    let onAction: (LoanDetailAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            termsChips
            actions
            breakdown
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Теги условий

    /// Чипсы — тот же компонент, что в форме условий (`AccountSelectionChip`), в невыбранном
    /// состоянии: здесь они читаются как теги. Нажатие ведёт в «Условия кредита» — иначе это была
    /// бы кнопка без действия.
    private var termsChips: some View {
        HStack(spacing: AppSpacing.s) {
            AccountSelectionChip(title: rateChip, isSelected: false) { onAction(.terms) }
            AccountSelectionChip(title: termChip, isSelected: false) { onAction(.terms) }
            AccountSelectionChip(title: scheduleTypeChip, isSelected: false) { onAction(.terms) }
        }
    }

    private var rateChip: String {
        String(
            format: L("accounts_core.loan.detail.rate_chip_format"),
            locale: AppLocalization.currentAppLocale,
            NSDecimalNumber(decimal: presentation.annualRatePercent).doubleValue
        )
    }

    private var termChip: String {
        String(
            format: L("accounts_core.loan.detail.term_chip_format"),
            locale: AppLocalization.currentAppLocale,
            presentation.termMonths,
            presentation.paymentsAhead
        )
    }

    private var scheduleTypeChip: String {
        switch presentation.scheduleType {
        case .annuity: L("accounts_core.loan.detail.schedule_type.annuity")
        case .differentiated: L("accounts_core.loan.detail.schedule_type.differentiated")
        }
    }

    // MARK: - Кнопки

    private var actions: some View {
        HStack(spacing: AppSpacing.s) {
            Button { onAction(.payment) } label: {
                actionLabel(
                    L("accounts_core.loan.detail.action.payment"),
                    foreground: LoanScreenStyle.accentContrast,
                    background: LoanScreenStyle.accent
                )
            }
            .buttonStyle(.plain)
            .disabled(presentation.nextPayment == nil)
            .opacity(presentation.nextPayment == nil ? 0.4 : 1)

            // Досрочка доступна, пока долг не погашен: лист сам решит, досрочное это погашение
            // или недоплата, — но при нулевом остатке вносить уже нечего.
            Button { onAction(.prepayment) } label: {
                actionLabel(
                    L("accounts_core.loan.detail.action.prepayment"),
                    foreground: AppColors.textPrimary,
                    background: LoanScreenStyle.quietFill
                )
            }
            .buttonStyle(.plain)
            .disabled(presentation.outstandingPrincipal <= 0)
            .opacity(presentation.outstandingPrincipal <= 0 ? 0.4 : 1)
        }
    }

    private func actionLabel(_ title: String, foreground: Color, background: Color) -> some View {
        Text(title)
            .font(.millioBodySemibold)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: LoanScreenStyle.buttonHeight)
            .padding(.horizontal, AppSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                    .fill(background)
            )
    }

    // MARK: - Разбивка платежа

    /// Точки-легенды — тот же цветовой словарь, что у двухцветной полосы графика (`LoanShareBar`).
    private var breakdown: some View {
        AccountDetailsBoxCard {
            LoanBreakdownRow(
                title: L("accounts_core.loan.detail.payment_principal"),
                value: presentation.nextPaymentPrincipal.map(presentation.money) ?? emptyValue,
                legendColor: LoanScreenStyle.principalColor
            )
            AccountDetailsDivider()
            LoanBreakdownRow(
                title: L("accounts_core.loan.detail.payment_interest"),
                value: presentation.nextPaymentInterest.map(presentation.money) ?? emptyValue,
                legendColor: LoanScreenStyle.interestColor
            )
            AccountDetailsDivider()
            scheduleRow
            AccountDetailsDivider()
            LoanBreakdownRow(
                title: L("accounts_core.loan.detail.paid_interest"),
                value: presentation.money(presentation.paidInterestTotal)
            )
        }
    }

    private var emptyValue: String { L("accounts_core.loan_form.value_empty") }

    /// Строка перехода в график (Ф5). Число впереди — то же, что считает витрина графика:
    /// оба берут «сколько осталось» из одного `remainingTerms`, поэтому строка и экран сходятся.
    private var scheduleRow: some View {
        Button { onAction(.schedule) } label: {
            HStack {
                Text(L("accounts_core.loan.detail.schedule"))
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: AppSpacing.s)
                Text(String(
                    format: L("accounts_core.loan.detail.schedule_ahead_format"),
                    presentation.paymentsAhead
                ))
                .font(.millioBody)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.millioCaption2)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.l)
    }
}
