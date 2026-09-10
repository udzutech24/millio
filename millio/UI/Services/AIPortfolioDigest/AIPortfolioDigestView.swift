//
//  AIPortfolioDigestView.swift
//  millio
//

import SwiftData
import SwiftUI

/// Обзор портфеля одной валюты: цифры с устройства, формулировка модели сверху, дисклеймер всегда.
/// Комплаенс: единственное действие на экране — навигация к позиции; ничего, что подталкивает к сделке.
struct AIPortfolioDigestView: View {
    @StateObject private var viewModel: AIPortfolioDigestViewModel
    private let modelContext: ModelContext
    @AppStorage("finance_amount_hidden") private var isAmountHidden: Bool = false
    @State private var openedAccountID: UUID?

    init(currency: String, modelContext: ModelContext, client: any AIPortfolioDigestClient) {
        self.modelContext = modelContext
        let source = AIPortfolioDigestFiguresSource(modelContext: modelContext, currency: currency)
        _viewModel = StateObject(wrappedValue: AIPortfolioDigestViewModel(
            currency: currency,
            figuresProvider: { source.figures(for: $0) },
            client: client
        ))
    }

    static func makeClient(diContainer: DIContainer?) -> any AIPortfolioDigestClient {
        guard let diContainer else { return UnavailableAIPortfolioDigestClient() }
        return BackendAIPortfolioDigestClient(
            authService: diContainer.authService,
            configurationProvider: diContainer.apiClientFactory.authConfigurationProvider()
        )
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    if let figures = viewModel.figures {
                        windowPicker
                        figuresCard(figures)
                        textSection(figures)
                        positionsCard(figures)
                    } else {
                        Text(String(format: L("ai.portfolio.empty_format"), viewModel.currency))
                            .font(Font.millioCalloutRegular)
                            .foregroundStyle(AppColors.textSecondary.opacity(0.75))
                    }

                    Text(viewModel.disclaimer)
                        .font(Font.millioCaption2Regular)
                        .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("aiPortfolio.disclaimer")
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.l)
            }
        }
        .navigationTitle(L("ai.portfolio.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { viewModel.open() }
        .navigationDestination(item: $openedAccountID) { accountID in
            if let account = account(withID: accountID) {
                AccountDetailView(account: account, modelContext: modelContext)
            }
        }
    }

    // MARK: - Окно

    private var windowPicker: some View {
        HStack(spacing: AppSpacing.s) {
            ForEach(AIPortfolioWindow.allCases) { window in
                let isSelected = viewModel.window == window
                Button {
                    withAnimation(AppAnimation.spring) {
                        viewModel.select(window)
                    }
                } label: {
                    Text(title(for: window))
                        .font(Font.millioCalloutSemibold)
                        .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.s)
                        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.12 : 0.04)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiPortfolio.window.\(window.rawValue)")
            }
        }
    }

    private func title(for window: AIPortfolioWindow) -> String {
        switch window {
        case .month: return L("ai.portfolio.window.month")
        case .quarter: return L("ai.portfolio.window.quarter")
        case .year: return L("ai.portfolio.window.year")
        }
    }

    private func changeTitle(for window: AIPortfolioWindow) -> String {
        switch window {
        case .month: return L("ai.portfolio.change.month")
        case .quarter: return L("ai.portfolio.change.quarter")
        case .year: return L("ai.portfolio.change.year")
        }
    }

    // MARK: - Цифры

    private func figuresCard(_ figures: AIPortfolioFigures) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            Text(String(format: L("ai.portfolio.value_format"), figures.currency))
                .font(Font.millioCaption2Medium)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))

            Text(AIPortfolioDigestFormatting.money(figures.value, currency: figures.currency, isHidden: isAmountHidden))
                .font(Font.millioTitle)
                .monospacedDigit()
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            HStack(spacing: AppSpacing.s) {
                Text(changeTitle(for: figures.window))
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)

                Spacer(minLength: AppSpacing.xs)

                Text(changeText(amount: figures.changeAmount, percent: figures.changePercent, currency: figures.currency))
                    .font(Font.millioSubheadline)
                    .monospacedDigit()
                    .foregroundStyle(tint(for: figures.changeAmount))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            Text(L("ai.portfolio.change.caption"))
                .font(Font.millioCaption2Regular)
                .foregroundStyle(AppColors.textSecondary.opacity(0.6))

            if !figures.excludedCurrencies.isEmpty {
                Text(String(format: L("ai.portfolio.excluded_format"), figures.excludedCurrencies.joined(separator: ", ")))
                    .font(Font.millioCaption2Regular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.6))
            }
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceChromeCardBackground())
    }

    private func changeText(amount: Decimal, percent: Decimal, currency: String) -> String {
        AIPortfolioDigestFormatting.signedMoney(amount, currency: currency, isHidden: isAmountHidden)
            + " · "
            + AIPortfolioDigestFormatting.signedPercent(percent)
    }

    private func tint(for value: Decimal) -> Color {
        if value > 0 { return AppColors.positiveColor }
        if value < 0 { return AppColors.negativeColor }
        return AppColors.textSecondary
    }

    // MARK: - Текст модели

    @ViewBuilder
    private func textSection(_ figures: AIPortfolioFigures) -> some View {
        if let text = viewModel.text {
            VStack(alignment: .leading, spacing: AppSpacing.m) {
                if let headline = text.headline {
                    Text(headline)
                        .font(Font.millioHeadline)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(text.notes) { note in
                    noteRow(note, figures: figures)
                }
            }
            .padding(AppSpacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FinanceChromeCardBackground())
        } else {
            // `filtered` выглядит так же, как офлайн: цифры без текста, без объяснений про фильтр.
            HStack(spacing: AppSpacing.s) {
                if viewModel.isLoadingText {
                    ProgressView().controlSize(.small).tint(AppColors.textSecondary)
                }
                Text(viewModel.isLoadingText ? L("ai.portfolio.loading") : L("ai.summary.numbers_only"))
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.75))
            }
            .padding(.horizontal, AppSpacing.xs)
        }
    }

    private func noteRow(_ note: AIPortfolioDigestNote, figures: AIPortfolioFigures) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            // Цветом вид заметки не кодируем: зелёный/красный у факта о структуре читался бы как оценка.
            Image(systemName: icon(for: note.kind))
                .font(Font.millioCaption2)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                .frame(width: AppSpacing.l, alignment: .center)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(note.text)
                    .font(Font.millioBodyRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let position = position(for: note, in: figures) {
                    Button {
                        openedAccountID = position.accountID
                    } label: {
                        Text(L("ai.portfolio.open_position"))
                            .font(Font.millioCaption2Medium)
                            .foregroundStyle(AppColors.textPrimary.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aiPortfolio.note.openPosition")
                }
            }
        }
    }

    private func icon(for kind: AIPortfolioNoteKind) -> String {
        switch kind {
        case .movement: return "arrow.up.arrow.down"
        case .structure: return "square.grid.2x2"
        case .concentration: return "chart.pie"
        }
    }

    private func position(for note: AIPortfolioDigestNote, in figures: AIPortfolioFigures) -> AIPortfolioPositionFigures? {
        guard let symbol = note.symbol?.uppercased(), !symbol.isEmpty else { return nil }
        return figures.positions.first { $0.symbol == symbol }
    }

    // MARK: - Позиции

    private func positionsCard(_ figures: AIPortfolioFigures) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(L("ai.portfolio.positions.title"))
                .font(Font.millioCaption2Medium)
                .foregroundStyle(AppColors.textSecondary.opacity(0.7))

            ForEach(figures.positions) { position in
                Button {
                    openedAccountID = position.accountID
                } label: {
                    positionRow(position, currency: figures.currency)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("aiPortfolio.position.\(position.symbol)")
            }
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceChromeCardBackground())
    }

    private func positionRow(_ position: AIPortfolioPositionFigures, currency: String) -> some View {
        HStack(spacing: AppSpacing.s) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(position.symbol)
                    .font(Font.millioCalloutSemibold)
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(String(format: L("ai.portfolio.share_format"), AIPortfolioDigestFormatting.percent(position.sharePercent)))
                    .font(Font.millioCaption2Regular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
            }

            Spacer(minLength: AppSpacing.xs)

            VStack(alignment: .trailing, spacing: AppSpacing.xs) {
                Text(AIPortfolioDigestFormatting.money(position.value, currency: currency, isHidden: isAmountHidden))
                    .font(Font.millioCalloutRegular)
                    .monospacedDigit()
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(AIPortfolioDigestFormatting.signedPercent(position.changePercent))
                    .font(Font.millioCaption2Regular)
                    .monospacedDigit()
                    .foregroundStyle(tint(for: position.changePercent))
            }

            Image(systemName: "chevron.right")
                .font(Font.millioCaption2)
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
        }
        .contentShape(Rectangle())
    }

    private func account(withID id: UUID) -> Account? {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
