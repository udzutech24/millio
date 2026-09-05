import SwiftUI

/// Экран «График платежей» (макет, ЭКРАН 3). Дамб-вью: все цифры уже посчитаны витриной.
///
/// Строки рисуются целиком (до 60 у стандартного кредита) обычным `VStack`: ленивая загрузка на
/// таком объёме экономила бы нечего, а `LazyVStack` внутри `ScrollView` ломает подсветку
/// текущего периода при возврате на экран.
struct LoanScheduleView: View {
    let presentation: LoanSchedulePresentation

    var body: some View {
        ZStack {
            GradientBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.xl) {
                    if presentation.rows.isEmpty {
                        emptyState
                    } else {
                        table
                        legend
                    }
                    summaryCard
                }
                .padding(AppSpacing.l)
            }
        }
        .navigationTitle(L("accounts_core.loan.detail.schedule"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Таблица

    private var table: some View {
        AccountDetailsBoxCard {
            VStack(spacing: 0) {
                ForEach(presentation.rows) { row in
                    LoanScheduleRowView(row: row)
                }
            }
            .padding(.vertical, AppSpacing.s)
            .padding(.horizontal, AppSpacing.s)
        }
    }

    // MARK: - Легенда

    private var legend: some View {
        HStack(spacing: AppSpacing.l) {
            legendItem(
                color: LoanScreenStyle.principalColor,
                title: L("accounts_core.loan.schedule.legend.principal")
            )
            legendItem(
                color: LoanScreenStyle.interestColor,
                title: L("accounts_core.loan.schedule.legend.interest")
            )
        }
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title)
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    // MARK: - Итог

    private var summaryCard: some View {
        AccountDetailsBoxCard {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("accounts_core.loan.schedule.overpayment"))
                    .font(.millioCaption2)
                    .foregroundStyle(AppColors.textTertiary)
                    .textCase(.uppercase)
                Text(presentation.overpaymentText)
                    .font(.millioTitle)
                    .foregroundStyle(LoanScreenStyle.interestColor)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(String(
                    format: L("accounts_core.loan.schedule.overpayment_note_format"),
                    presentation.overpaymentShareText
                ))
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(AppSpacing.l)
        }
    }

    private var emptyState: some View {
        Text(L("accounts_core.loan.schedule.empty"))
            .font(.millioBodyRegular)
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Строка графика: месяц → двухцветная полоса → сумма платежа.
private struct LoanScheduleRowView: View {
    let row: LoanScheduleRowPresentation

    var body: some View {
        HStack(spacing: AppSpacing.m) {
            Text(row.monthLabel)
                .font(row.isCurrent ? .millioCalloutSemibold : .millioCallout)
                .foregroundStyle(row.isCurrent ? LoanScreenStyle.accent : AppColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: LoanScreenStyle.scheduleMonthColumnWidth, alignment: .leading)
            LoanShareBar(principalShare: row.principalShare)
            Text(row.paymentText)
                .font(.millioCallout)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: LoanScreenStyle.scheduleAmountColumnWidth, alignment: .trailing)
        }
        .frame(minHeight: LoanScreenStyle.scheduleRowHeight)
        .padding(.horizontal, AppSpacing.s)
        .background {
            if row.isCurrent {
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(LoanScreenStyle.currentRowFill)
            }
        }
        .opacity(row.isPaid ? LoanScreenStyle.paidRowOpacity : 1)
        .accessibilityElement(children: .combine)
    }
}
