import SwiftUI

/// Одноцветный прогресс-бар hero-карточки счёта.
///
/// Вынесен из `DepositHeroContent.progressBar`, где жил приватным методом: та же шкала нужна
/// прогрессу погашенного тела кредита, а вторая копия разъехалась бы с первым же изменением
/// толщины или прозрачности дорожки.
struct AccountHeroProgressBar: View {
    let progress: Decimal
    /// Заливка отличается по сервису: у вклада белая, у кредита — медь.
    var fill: Color = .white

    var body: some View {
        let clamped = min(max(NSDecimalNumber(decimal: progress).doubleValue, 0), 1)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.22))
                Capsule().fill(fill).frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 4)
    }
}

/// Плитка метрики hero-карточки: подпись → значение → уточнение.
///
/// Вынесена из `DepositHeroContent`, где одна и та же плашка была написана трижды
/// (`nextAccrualMetric` / `maturityMetric` / `metricCard`). Метрика 2×1 собирается из двух таких
/// плиток внутри `ViewThatFits`, как это делает `DepositHeroContent.metricsRow`.
struct AccountHeroMetricTile: View {
    let title: String
    let value: String
    var caption: String?
    var valueColor: Color = .white

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(title)
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.68))
            Text(value)
                .font(.millioHeadline)
                .foregroundStyle(valueColor)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            if let caption {
                Text(caption)
                    .font(.millioMicro)
                    .foregroundStyle(.white.opacity(0.58))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.m)
        .frame(minHeight: 92, alignment: .topLeading)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous))
    }
}
