import SwiftUI

/// Подтверждение планового платежа — лист снизу с разбивкой, а не системный алерт.
///
/// Правило владельца (`feedback-bottom-sheet-under-thumb`): меню и подтверждения живут под большим
/// пальцем. Алерт вдобавок не смог бы показать разбивку «тело / проценты», ради которой этот шаг и
/// существует: человек должен видеть, что долг уменьшится не на всю сумму платежа.
struct LoanPaymentConfirmSheet: View {
    let presentation: LoanDetailPresentation
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    /// Высота листа фиксированная: состав строк известен заранее, а `.medium` оставил бы пустой
    /// хвост снизу (тот же приём, что в `AccountActionsSheet`).
    private var sheetHeight: CGFloat { 430 }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            header
            AccountDetailsBoxCard {
                LoanBreakdownRow(
                    title: L("accounts_core.loan.detail.payment_principal"),
                    value: presentation.money(principalPart),
                    legendColor: LoanScreenStyle.principalColor
                )
                AccountDetailsDivider()
                LoanBreakdownRow(
                    title: L("accounts_core.loan.detail.payment_interest"),
                    value: presentation.money(interestPart),
                    legendColor: LoanScreenStyle.interestColor
                )
                AccountDetailsDivider()
                LoanBreakdownRow(
                    title: L("accounts_core.loan.detail.debt_after"),
                    value: presentation.money(max(presentation.outstandingPrincipal - principalPart, 0))
                )
            }
            Spacer(minLength: 0)
            confirmButton
            cancelButton
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.xl)
        .padding(.bottom, AppSpacing.m)
        .presentationDetents([.height(sheetHeight)])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("accounts_core.loan.detail.action.payment"))
                .font(.millioCaption2)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
            Text(presentation.money(payment))
                .font(.millioTitle)
                .foregroundStyle(AppColors.textPrimary)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let date = presentation.nextPaymentDate {
                Text(date.formatted(date: .long, time: .omitted))
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }

    private var confirmButton: some View {
        Button {
            onConfirm()
        } label: {
            Text(String(
                format: L("accounts_core.loan.detail.confirm_payment_format"),
                presentation.money(payment)
            ))
            .font(.millioBodySemibold)
            .foregroundStyle(LoanScreenStyle.accentContrast)
            .frame(maxWidth: .infinity, minHeight: LoanScreenStyle.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: LoanScreenStyle.buttonCornerRadius, style: .continuous)
                    .fill(LoanScreenStyle.accent)
            )
        }
        .buttonStyle(.plain)
    }

    private var cancelButton: some View {
        Button(L("accounts_core.detail.sheet.cancel"), action: onDismiss)
            .font(.millioBodySemibold)
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(LoanScreenStyle.quietFill))
    }

    private var payment: Decimal { presentation.nextPayment ?? 0 }
    private var principalPart: Decimal { presentation.nextPaymentPrincipal ?? 0 }
    private var interestPart: Decimal { presentation.nextPaymentInterest ?? 0 }
}
