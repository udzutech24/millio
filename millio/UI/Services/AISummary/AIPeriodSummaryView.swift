//
//  AIPeriodSummaryView.swift
//  millio
//

import SwiftUI

/// Экран итогов периода. Цифры считаются на устройстве и показываются в любом состоянии —
/// офлайн и ошибка сети убирают только формулировку, но не содержимое экрана.
struct AIPeriodSummaryView: View {
    @ObservedObject var viewModel: AIPeriodSummaryViewModel
    @AppStorage("finance_amount_hidden") private var isAmountHidden: Bool = false

    private var peak: Double { max(viewModel.figures.income, viewModel.figures.expense) }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    periodPicker
                    figuresCard
                    textSection
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.l)
            }
        }
        .navigationTitle(L("ai.summary.screen.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.refresh() }
    }

    // MARK: - Переключатель периода

    private var periodPicker: some View {
        HStack(spacing: AppSpacing.s) {
            ForEach(AIPeriodKind.allCases) { kind in
                Button {
                    withAnimation(AppAnimation.spring) {
                        viewModel.select(kind)
                    }
                } label: {
                    Text(title(for: kind))
                        .font(Font.millioCalloutSemibold)
                        .foregroundStyle(
                            viewModel.kind == kind ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.7)
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.s)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(viewModel.kind == kind ? 0.12 : 0.04))
                                .overlay(
                                    Capsule().stroke(
                                        Color.white.opacity(viewModel.kind == kind ? 0.18 : 0.10),
                                        lineWidth: 0.7
                                    )
                                )
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiSummary.period.\(kind.rawValue)")
            }
        }
    }

    private func title(for kind: AIPeriodKind) -> String {
        switch kind {
        case .month: return L("ai.summary.period.month")
        case .quarter: return L("ai.summary.period.quarter")
        }
    }

    // MARK: - Цифры

    private var figuresCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(AIPeriodSummaryFormatting.periodTitle(for: viewModel.period))
                .font(Font.millioCaption2Medium)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))

            AIPeriodAmountBar(
                title: L("cashflow.income"),
                value: viewModel.figures.income,
                share: AIPeriodSummaryFormatting.barShare(viewModel.figures.income, peak: peak),
                tint: AppColors.positiveColor,
                currency: viewModel.currency,
                isAmountHidden: isAmountHidden
            )

            AIPeriodAmountBar(
                title: L("cashflow.expense"),
                value: viewModel.figures.expense,
                share: AIPeriodSummaryFormatting.barShare(viewModel.figures.expense, peak: peak),
                tint: AppColors.negativeColor,
                currency: viewModel.currency,
                isAmountHidden: isAmountHidden
            )

            Divider().overlay(Color.white.opacity(0.10))

            totalRow(
                title: L("ai.summary.net"),
                value: AIPeriodSummaryFormatting.signedMoney(
                    viewModel.figures.net,
                    currencyCode: viewModel.currency,
                    isHidden: isAmountHidden
                ),
                tint: viewModel.figures.net >= 0 ? AppColors.positiveColor : AppColors.negativeColor
            )

            totalRow(
                title: L("ai.summary.balance_end"),
                value: AIPeriodSummaryFormatting.money(
                    viewModel.figures.balanceEnd,
                    currencyCode: viewModel.currency,
                    isHidden: isAmountHidden
                ),
                tint: AppColors.textPrimary
            )
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceChromeCardBackground())
    }

    private func totalRow(title: String, value: String, tint: Color) -> some View {
        HStack(spacing: AppSpacing.s) {
            Text(title)
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: AppSpacing.xs)

            Text(value)
                .font(Font.millioSubheadline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - Текст модели

    @ViewBuilder
    private var textSection: some View {
        if let text = viewModel.text, !text.isEmpty {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                if let headline = text.headline, !headline.isEmpty {
                    Text(headline)
                        .font(Font.millioHeadline)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(text.observations) { observation in
                    observationRow(observation)
                }
            }
            .padding(AppSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceChromeCardBackground())
        } else {
            HStack(spacing: AppSpacing.s) {
                if viewModel.isLoadingText {
                    ProgressView().controlSize(.small).tint(AppColors.textSecondary)
                }
                Text(viewModel.isLoadingText ? L("ai.summary.loading") : L("ai.summary.numbers_only"))
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.75))
            }
            .padding(.horizontal, AppSpacing.xs)
        }
    }

    private func observationRow(_ observation: AIPeriodObservation) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            // Цветом вид наблюдения не кодируем: «рост» бывает и у дохода, и у расхода —
            // зелёный/красный врал бы в половине случаев. Отличаем только иконкой.
            Image(systemName: icon(for: observation.kind))
                .font(Font.millioCaption2)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                .frame(width: AppSpacing.l, alignment: .center)

            Text(observation.text)
                .font(Font.millioBodyRegular)
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func icon(for kind: AIObservationKind) -> String {
        switch kind {
        case .growth: return "arrow.up.right"
        case .drop: return "arrow.down.right"
        case .steady: return "equal"
        }
    }
}
