import SwiftUI

/// Начинка hero-карточки кредита (макет, ЭКРАН 1): остаток → прогресс погашенного тела → метрики.
///
/// Рисуется как `customContent` общего `AccountHeroCardView` — ровно тем же способом, что у вклада:
/// носитель (градиент, скругления, паддинги) остаётся общим для всех типов счетов, меняется только
/// содержимое. Имя счёта здесь не дублируется, оно уже в navigation title.
///
/// Знак: в ленте кредит хранится отрицательным балансом, но человеку показываем «сколько осталось
/// выплатить» — положительную величину долга. Обратное преобразование живёт в `AccountDetailView`,
/// эта вью получает уже готовую витрину.
struct LoanHeroContent: View {
    let presentation: LoanDetailPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            outstandingBlock
            hairline
            progressBlock
            if nextPaymentValue != nil {
                hairline
                metricsRow
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
    }

    private var outstandingBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("accounts_core.loan.detail.outstanding"))
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.68))
            Text(presentation.money(presentation.outstandingPrincipal))
                .font(.millioTitle)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle)
                    .font(.millioCaptionRegular)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    /// «из 1 200 000 ₽ · закроется 15 марта 2031». Дата закрытия пропадает у кредита с открытым
    /// графиком (ручной платёж без срока) — тогда остаётся только исходная сумма.
    private var subtitle: String? {
        guard presentation.principal > 0 else { return nil }
        var parts = [String(
            format: L("accounts_core.loan.detail.of_principal_format"),
            presentation.money(presentation.principal)
        )]
        if let payoffDate = presentation.payoffDate {
            parts.append(String(
                format: L("accounts_core.loan.detail.payoff_format"),
                payoffDate.formatted(date: .long, time: .omitted)
            ))
        }
        return parts.joined(separator: " · ")
    }

    private var progressBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            AccountHeroProgressBar(progress: presentation.progress, fill: LoanScreenStyle.accent)
            HStack {
                Text(String(
                    format: L("accounts_core.loan.detail.paid_principal_format"),
                    presentation.money(presentation.paidPrincipal)
                ))
                Spacer(minLength: AppSpacing.s)
                Text(presentation.progressText)
            }
            .font(.millioMicro)
            .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var nextPaymentValue: Decimal? { presentation.nextPayment }

    @ViewBuilder
    private var metricsRow: some View {
        if let payment = nextPaymentValue {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.s) { metricTiles(payment: payment) }
                VStack(spacing: AppSpacing.s) { metricTiles(payment: payment) }
            }
        }
    }

    @ViewBuilder
    private func metricTiles(payment: Decimal) -> some View {
        AccountHeroMetricTile(
            title: L("accounts_core.loan.detail.next_payment"),
            value: presentation.money(payment)
        )
        AccountHeroMetricTile(
            title: L("accounts_core.loan.detail.next_payment_date"),
            value: presentation.nextPaymentDate?.formatted(date: .abbreviated, time: .omitted)
                ?? L("accounts_core.loan_form.value_empty")
        )
    }
}
