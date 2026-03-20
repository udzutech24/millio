//
//  ProChartUpsellView.swift
//  millio
//
//  Единый, ненавязчивый upsell для PRO-графиков.
//  Используется в местах, где график недоступен без подписки, чтобы стиль и CTA были консистентными.
//

import SwiftUI

/// Настройки размеров/типографики для upsell-экрана PRO-графиков.
/// Вынесено отдельно, чтобы:
///  - держать единый стиль во всех местах,
///  - было проще тестировать и менять без "магических чисел" по проекту.
struct ProChartUpsellMetrics: Equatable {
    enum Size: Equatable {
        case compact
        case regular
    }

    let iconPointSize: CGFloat
    let titlePointSize: CGFloat
    let subtitlePointSize: CGFloat
    let ctaPointSize: CGFloat
    let verticalSpacing: CGFloat
    let ctaVerticalPadding: CGFloat

    static func make(for size: Size) -> ProChartUpsellMetrics {
        switch size {
        case .compact:
            return .init(
                iconPointSize: 22,
                titlePointSize: 15,
                subtitlePointSize: 12,
                ctaPointSize: 13,
                verticalSpacing: 10,
                ctaVerticalPadding: 8
            )
        case .regular:
            return .init(
                iconPointSize: 40,
                titlePointSize: 16,
                subtitlePointSize: 14,
                ctaPointSize: 15,
                verticalSpacing: 14,
                ctaVerticalPadding: 11
            )
        }
    }
}

/// Ненавязчивый upsell-блок для ситуаций, когда график доступен только в PRO.
/// Внешний фон (карточка/материал) задаётся снаружи — компонент отвечает только за контент и CTA.
struct ProChartUpsellView: View {
    let titleKey: LocalizedStringKey?
    let subtitleKey: LocalizedStringKey
    let ctaKey: LocalizedStringKey
    let size: ProChartUpsellMetrics.Size
    let onTapCTA: () -> Void

    private var metrics: ProChartUpsellMetrics {
        ProChartUpsellMetrics.make(for: size)
    }

    var body: some View {
        VStack(spacing: metrics.verticalSpacing) {
            Image(systemName: "lock")
                .font(.system(size: metrics.iconPointSize, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)

            if let titleKey {
                Text(titleKey)
                    .font(.system(size: metrics.titlePointSize, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
            }

            Text(subtitleKey)
                .font(.system(size: metrics.subtitlePointSize))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onTapCTA) {
                Text(ctaKey)
                    .font(.system(size: metrics.ctaPointSize, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, metrics.ctaVerticalPadding)
                    .background(
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color(hex: "2A8CFF"), Color(hex: "4B76FF"), Color(hex: "7D72FF")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                            )
                    )
                    .shadow(color: Color(hex: "2A8CFF").opacity(0.24), radius: 14, x: 0, y: 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(ctaKey))
        }
        .padding(.horizontal, 20)
    }
}
