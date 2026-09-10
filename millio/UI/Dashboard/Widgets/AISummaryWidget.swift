//
//  AISummaryWidget.swift
//  millio
//

import SwiftUI

/// Данные карточки итогов на дашборде. Карточка — «немая» view, как и остальные виджеты:
/// считает и грузит текст `AIPeriodSummaryViewModel` на уровне таба.
struct AISummaryCardModel: Equatable {
    var periodTitle: String = ""
    /// Заголовок итогов, а без него — первая заметка (`AIPeriodSummaryText.leadLine`).
    var headline: String?
    var income: Double = 0
    var expense: Double = 0
    var net: Double = 0
    var currency: String = "RUB"
    var isLoadingText: Bool = false
}

struct AISummaryWidget: View {
    let model: AISummaryCardModel
    var isAmountHidden: Bool = false
    var onTap: (() -> Void)? = nil
    /// Вход в диалог прямо с карточки. Отдельная кнопка, а не жест поверх карточки:
    /// тап по остальной карточке по-прежнему ведёт в итоги.
    var onAsk: (() -> Void)? = nil

    private var peak: Double { max(model.income, model.expense) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onTap?()
            } label: {
                VStack(alignment: .leading, spacing: AppSpacing.m) {
                    header
                    headlineRow
                    amountsRow
                }
                .padding(.horizontal, AppSpacing.xl)
                .padding(.top, AppSpacing.l)
                .padding(.bottom, onAsk == nil ? AppSpacing.l : AppSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onTap == nil)
            .accessibilityIdentifier("dashboard.aiSummaryWidget")

            if let onAsk {
                askRow(action: onAsk)
            }
        }
        .background(DashboardCardBackground())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: AppSpacing.s) {
            Image(systemName: "sparkles")
                .font(Font.millioCallout)
                .foregroundStyle(
                    LinearGradient(colors: AppColors.financesGradient, startPoint: .leading, endPoint: .trailing)
                )

            // Название приложения — имя собственное, не переводится.
            Text(verbatim: "millio")
                .font(Font.millioCalloutSemibold)
                .foregroundStyle(AppColors.textPrimary)

            Text(model.periodTitle)
                .font(Font.millioCaption2Medium)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                .lineLimit(1)

            Spacer(minLength: AppSpacing.xs)

            Image(systemName: "chevron.right")
                .font(Font.millioCaption2)
                .foregroundStyle(AppColors.textSecondary.opacity(0.6))
        }
    }

    @ViewBuilder
    private var headlineRow: some View {
        if let headline = model.headline, !headline.isEmpty {
            Text(headline)
                .font(Font.millioBodyRegular)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(model.isLoadingText ? L("ai.summary.loading") : L("ai.summary.numbers_only"))
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary.opacity(0.75))
                .lineLimit(1)
        }
    }

    // MARK: - Вход в диалог

    private func askRow(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                Divider().overlay(Color.white.opacity(0.08))

                HStack(spacing: AppSpacing.s) {
                    AIChatOrb(diameter: 20, isActive: false)
                    Text(L("ai.chat.dashboard.ask"))
                        .font(Font.millioCalloutRegular)
                        .foregroundStyle(AppColors.textSecondary.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: AppSpacing.xs)
                }
            }
            .padding(.horizontal, AppSpacing.xl)
            .padding(.bottom, AppSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.aiSummaryWidget.ask")
    }

    // MARK: - Суммы с полосами

    private var amountsRow: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            AIPeriodAmountBar(
                title: L("cashflow.income"),
                value: model.income,
                share: AIPeriodSummaryFormatting.barShare(model.income, peak: peak),
                tint: AppColors.positiveColor,
                currency: model.currency,
                isAmountHidden: isAmountHidden
            )
            AIPeriodAmountBar(
                title: L("cashflow.expense"),
                value: model.expense,
                share: AIPeriodSummaryFormatting.barShare(model.expense, peak: peak),
                tint: AppColors.negativeColor,
                currency: model.currency,
                isAmountHidden: isAmountHidden
            )
        }
    }
}

/// Строка «подпись — сумма» с тонкой полосой доли. Отдельного фона у строки нет намеренно:
/// вложенные панели внутри карточки утяжеляют дашборд.
struct AIPeriodAmountBar: View {
    let title: String
    let value: Double
    let share: Double
    let tint: Color
    let currency: String
    var isAmountHidden: Bool = false

    private let barHeight: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            HStack(spacing: AppSpacing.s) {
                Text(title)
                    .font(Font.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))

                Spacer(minLength: AppSpacing.xs)

                Text(AIPeriodSummaryFormatting.money(value, currencyCode: currency, isHidden: isAmountHidden))
                    .font(Font.millioCalloutSemibold)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(tint.opacity(0.75))
                        .frame(width: max(0, proxy.size.width * share))
                }
            }
            .frame(height: barHeight)
        }
    }
}
