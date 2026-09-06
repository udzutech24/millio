import SwiftUI
import SwiftData

/// Прогноз вклада «грязными/чистыми».
extension AccountDetailView {
    // MARK: - Прогноз вклада «грязными/чистыми» (Фаза 3)

    var depositForecastSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(L("accounts_core.detail.deposit.forecast_title"))
                .font(.millioCaption)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                forecastRow(L("accounts_core.detail.deposit.accrued_total"), amount: accruedInterestTotal)

                if let monthlyGross = monthlyForecastGross {
                    forecastRow(L("accounts_core.detail.deposit.per_month_gross"), amount: monthlyGross)
                    forecastRow(L("accounts_core.detail.deposit.per_month_net"), amount: netAmount(monthlyGross))
                }

                if let termGross = termForecastGross {
                    forecastRow(L("accounts_core.detail.deposit.per_term_gross"), amount: termGross)
                    forecastRow(L("accounts_core.detail.deposit.per_term_net"), amount: netAmount(termGross))
                }

                Text(String(format: L("accounts_core.detail.deposit.tax_estimate_format"), "\(formattedAmount(yearlyTaxEstimateForThisAccount)) ₽"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(AppColors.textTertiary)
            }
            .padding(AppSpacing.m)
            .background(
                RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous)
                    .fill(AppColors.iconBackground)
            )
        }
    }

    func forecastRow(_ title: String, amount: Decimal) -> some View {
        HStack {
            Text(title)
                .font(.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
            Text("\(formattedAmount(amount)) \(account.currency)")
                .font(.millioBodySemibold)
                .foregroundStyle(AppColors.textPrimary)
        }
    }

    /// Форматтеры живут статически: `NumberFormatter()` в теле метода пересоздавался на КАЖДУЮ
    /// строку истории (сотни строк на пересчёт body). Локаль присваивается при каждом вызове —
    /// иначе смена языка в приложении не доехала бы до уже созданного форматтера.
}
