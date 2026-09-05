import SwiftUI
import Charts

/// Одна точка ценового графика позиции — только реальные дни из append-only кэша
/// `HistoricalAssetPrice` (см. `AccountMarketPriceService`). Синтетических точек не рисуем:
/// нет истории цен по символу → блок графика просто не показывается (см. `AccountDetailView`).
struct InvestmentPricePoint: Equatable {
    let date: Date
    let price: Double
}

/// Готовые к отрисовке данные hero-карточки рыночной позиции (Ф-редизайн деталки инвестиции).
/// Собирается в `AccountDetailView` из уже существующих `StockPositionSnapshot`/цены — эта
/// структура не считает P&L заново, только формирует то, что показать и как подписать.
struct InvestmentHeroPresentation: Equatable {
    let currency: String
    let currencySymbol: String
    /// Стоимость позиции = quantity × текущая цена (то самое число, что в hero-сумме и в тоталах).
    let positionValue: Decimal
    /// Прибыль капсулы = `stockSnapshot.totalReturn` (реализованный + нереализованный + дивиденды − комиссии).
    /// Второго определения прибыли на карточке больше нет — «Общий доход» и «Нереализованный P&L» сняты.
    let totalReturn: Decimal
    /// `nil`, если позиция полностью закрыта (`openCostBasis == 0`) — делить не на что.
    let returnPercent: Decimal?
    let quantity: Decimal
    let currentUnitPrice: Decimal
    let averageUnitCost: Decimal?
    let invested: Decimal
    let dividends: Decimal
    let realizedProfitLoss: Decimal
    let fees: Decimal
    /// `nil`, если нет данных по другим позициям в той же валюте — раздел «Доля в портфеле» скрыт,
    /// а не считается по неполным/сконвертированным данным.
    let portfolioSharePercent: Decimal?
    let sparkline: [InvestmentPricePoint]
    let sparklineMonths: Int
    let latestPriceAsOf: Date?
}

/// Начинка hero-карточки рыночной позиции. Рисуется ВНУТРИ `AccountHeroCardView` как
/// `customContent` — identity-строка счёта (имя/тикер/бейдж «Инвестиции») здесь не нужна: имя уже
/// в navigation title, а дублирующий тикер и статус «сегодня» были причиной тройного повтора
/// одних и тех же чисел на старом экране.
struct InvestmentHeroContent: View {
    let presentation: InvestmentHeroPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            valueBlock
            profitCapsule
            hairline
            positionRow
            if !presentation.sparkline.isEmpty {
                hairline
                priceChart
            }
            hairline
            summaryBlock
        }
    }

    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
    }

    // MARK: - Стоимость позиции

    private var valueBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("accounts_core.detail.market.position_value_label"))
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.68))
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(amountText(presentation.positionValue))
                    .font(.millioTitle)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(presentation.currencySymbol)
                    .font(.millioBody)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }

    // MARK: - Прибыль

    /// Тёмная капсула с фиксированным чёрным фоном — а не оттенком карточки: цвет hero выбирает
    /// пользователь в галерее оформления, и на светлых пресетах белый текст на светлой подложке
    /// нечитаем (владелец поймал это на скрине). Капсула обязана работать на любом акценте.
    private var profitCapsule: some View {
        HStack(spacing: AppSpacing.xs) {
            Image(systemName: presentation.totalReturn < 0 ? "arrow.down" : "arrow.up")
                .font(.millioCaption2Medium)
                .foregroundStyle(profitTintColor)
            Text(profitCapsuleText)
                .font(.millioCaption2Medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, AppSpacing.s)
        .padding(.vertical, AppSpacing.xs)
        .background(Capsule().fill(Color.black.opacity(0.28)))
    }

    private var profitTintColor: Color {
        presentation.totalReturn < 0 ? AppColors.negativeColor : AppColors.positiveColor
    }

    private var profitCapsuleText: String {
        var parts = [signedAmountText(presentation.totalReturn)]
        if let percent = presentation.returnPercent {
            parts.append(signedPercentText(percent))
        }
        return parts.joined(separator: " · ") + " " + L("accounts_core.detail.market.all_time_suffix")
    }

    // MARK: - Количество / средняя цена

    private var positionRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(L("accounts_core.detail.market.in_portfolio_label"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(.white.opacity(0.68))
                Text(inPortfolioText)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: AppSpacing.s)
            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text(L("accounts_core.detail.market.bought_at_label"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(.white.opacity(0.68))
                Text(presentation.averageUnitCost.map(amountText) ?? "—")
                    .font(.millioCalloutRegular)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }

    private var inPortfolioText: String {
        "\(quantityText(presentation.quantity)) \(L("accounts_core.detail.market.quantity_unit")) × \(amountText(presentation.currentUnitPrice))"
    }

    // MARK: - График цены

    private var priceChart: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Chart {
                ForEach(Array(presentation.sparkline.enumerated()), id: \.offset) { _, point in
                    AreaMark(x: .value("date", point.date), y: .value("price", point.price))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [chartColor.opacity(0.32), chartColor.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    LineMark(x: .value("date", point.date), y: .value("price", point.price))
                        .foregroundStyle(chartColor)
                        .interpolationMethod(.catmullRom)
                }
                if let last = presentation.sparkline.last {
                    PointMark(x: .value("date", last.date), y: .value("price", last.price))
                        .foregroundStyle(chartColor)
                        .symbolSize(36)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: 64)

            HStack {
                Text(L("accounts_core.detail.market.chart_period_months \(presentation.sparklineMonths)"))
                Spacer()
                if let asOf = presentation.latestPriceAsOf {
                    Text(String(format: L("accounts_core.detail.market.price_as_of_format"), asOf.formatted(date: .abbreviated, time: .shortened)))
                }
            }
            .font(.millioMicro)
            .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var chartColor: Color {
        guard let first = presentation.sparkline.first, let last = presentation.sparkline.last else {
            return .white.opacity(0.8)
        }
        return last.price < first.price ? AppColors.negativeColor : AppColors.positiveColor
    }

    // MARK: - Итоги

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            summaryRow(L("accounts_core.detail.market.invested_label"), value: amountText(presentation.invested))
            if presentation.dividends > 0 {
                summaryRow(L("accounts_core.detail.market.dividends_received_label"), value: amountText(presentation.dividends))
            }
            if let share = presentation.portfolioSharePercent {
                summaryRow(L("accounts_core.detail.market.portfolio_share_label"), value: percentText(share))
            }
            if presentation.realizedProfitLoss != 0 {
                summaryRow(
                    L("accounts_core.detail.market.realized_label"),
                    value: signedAmountText(presentation.realizedProfitLoss),
                    tone: presentation.realizedProfitLoss
                )
            }
            if presentation.fees > 0 {
                summaryRow(L("accounts_core.detail.market.fees_label"), value: amountText(presentation.fees))
            }
        }
    }

    private func summaryRow(_ title: String, value: String, tone: Decimal? = nil) -> some View {
        HStack {
            Text(title)
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.68))
            Spacer()
            Text(value)
                .font(.millioCalloutRegular)
                .foregroundStyle(
                    tone.map { $0 < 0 ? AppColors.negativeColor : ($0 > 0 ? AppColors.positiveColor : Color.white) } ?? .white
                )
        }
    }

    // MARK: - Форматирование

    /// Один символ валюты везде на карточке — тот же общий форматтер, что использует hero вклада.
    private func amountText(_ value: Decimal) -> String {
        DepositAmountTextFormatter.string(
            value,
            currency: presentation.currency,
            symbol: presentation.currencySymbol,
            locale: AppLocalization.currentAppLocale
        )
    }

    private func signedAmountText(_ value: Decimal) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + amountText(value)
    }

    private func quantityText(_ value: Decimal) -> String {
        value.formatted(
            .number
                .locale(AppLocalization.currentAppLocale)
                .grouping(.automatic)
                .precision(.fractionLength(0...4))
        )
    }

    private func percentText(_ value: Decimal) -> String {
        String(format: "%.2f%%", NSDecimalNumber(decimal: value).doubleValue)
    }

    private func signedPercentText(_ value: Decimal) -> String {
        let sign = value > 0 ? "+" : ""
        return sign + percentText(value)
    }
}
