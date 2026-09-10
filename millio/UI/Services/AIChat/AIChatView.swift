//
//  AIChatView.swift
//  millio
//

import SwiftUI

/// Экран чата. Цифры периода видны всегда — даже когда модель недоступна, экран остаётся
/// осмысленным: срез на месте, а вместо ответа стоит внятная причина и повтор.
struct AIChatView: View {
    @ObservedObject var viewModel: AIChatViewModel
    @AppStorage("finance_amount_hidden") private var isAmountHidden: Bool = false
    @State private var showsClearConfirmation = false

    /// Подсказки на пустом экране и чипы под ответом — заготовленные вопросы, а не действия
    /// в приложении: чат ничего не меняет в данных. Сравнения с прошлым периодом среди них нет
    /// намеренно: в срез чата прошлый период не входит, и модель пришлось бы угадывать цифры.
    private var suggestions: [String] {
        [
            L("ai.chat.suggestion.top_expense"),
            L("ai.chat.suggestion.savings"),
            L("ai.chat.suggestion.categories"),
            L("ai.chat.suggestion.cut")
        ]
    }

    private var followUps: [String] {
        [
            L("ai.chat.followup.why"),
            L("ai.chat.followup.next"),
            L("ai.chat.followup.shorter")
        ]
    }

    var body: some View {
        ZStack {
            GradientBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.l) {
                    AIChatContextCard(
                        periodTitle: AIPeriodSummaryFormatting.periodTitle(for: viewModel.snapshot.period),
                        figures: viewModel.snapshot.figures,
                        currency: viewModel.snapshot.currency,
                        isAmountHidden: isAmountHidden
                    )

                    if viewModel.isEmpty {
                        emptyState
                    } else {
                        conversation
                    }

                    failureRow
                }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.l)
            }
            // Лента сама держится низом при росте текста — скроллить на каждый токен вручную
            // означало бы пересчёт layout на каждом кадре печати.
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            AIChatComposer(
                text: $viewModel.draft,
                isSending: viewModel.isSending,
                canSend: viewModel.canSend,
                onSend: { viewModel.send(viewModel.draft) },
                onStop: { viewModel.stopGenerating() }
            )
        }
        .navigationTitle(Text(verbatim: "millio"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showsClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(Font.millioCallout)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel(L("ai.chat.clear"))
                    .accessibilityIdentifier("aiChat.clear")
                }
            }
        }
        // Подтверждение — листом снизу, как и остальные деструктивные действия приложения.
        .confirmationDialog(
            L("ai.chat.clear.confirm"),
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("ai.chat.clear"), role: .destructive) { viewModel.clearHistory() }
            Button(L("common.cancel"), role: .cancel) {}
        }
        .task { await viewModel.prepare() }
        // Ушли с экрана — генерацию гасим: иначе поток держит SSE-соединение и тратит лимит
        // запросов на ответ, который никто не прочитает.
        .onDisappear { viewModel.stopGenerating() }
    }

    // MARK: - Пусто

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            HStack {
                Spacer()
                AIChatOrb(diameter: 104, isActive: false)
                Spacer()
            }
            .padding(.top, AppSpacing.l)

            VStack(alignment: .leading, spacing: AppSpacing.s) {
                Text(L("ai.chat.empty.title"))
                    .font(Font.millioTitle3)
                    .foregroundStyle(AppColors.textPrimary)

                Text(L("ai.chat.empty.subtitle"))
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: AppSpacing.s) {
                ForEach(suggestions, id: \.self) { text in
                    AIChatSuggestionTile(text: text) { viewModel.send(text) }
                }
            }
        }
    }

    // MARK: - Диалог

    private var conversation: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            ForEach(viewModel.messages) { message in
                AIChatBubble(role: message.role, text: message.text)
                    .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
            }

            if let pending = viewModel.pendingAnswer {
                if pending.isEmpty {
                    thinkingRow
                } else {
                    AIChatBubble(role: .assistant, text: pending, isStreaming: true)
                }
            }

            if viewModel.pendingAnswer == nil,
               viewModel.failure == nil,
               viewModel.messages.last?.role == .assistant {
                followUpChips
            }

            Text(L("ai.chat.disclaimer"))
                .font(Font.millioCaption2Regular)
                .foregroundStyle(AppColors.textSecondary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var thinkingRow: some View {
        HStack(spacing: AppSpacing.s) {
            AIChatOrb(diameter: 22, isActive: true)
            Text(L("ai.chat.thinking"))
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary.opacity(0.75))
        }
    }

    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: AppSpacing.s) {
                ForEach(followUps, id: \.self) { text in
                    AIChatChip(text: text) { viewModel.send(text) }
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Отказ

    @ViewBuilder
    private var failureRow: some View {
        if let failure = viewModel.failure {
            HStack(alignment: .top, spacing: AppSpacing.s) {
                Image(systemName: "exclamationmark.circle")
                    .font(Font.millioCallout)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))

                Text(message(for: failure))
                    .font(Font.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppSpacing.xs)

                if viewModel.canRetry {
                    Button(L("ai.chat.retry")) { viewModel.retry() }
                        .font(Font.millioCalloutSemibold)
                        .foregroundStyle(FinanceScreenChrome.accentColor)
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("aiChat.retry")
                }
            }
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                    )
            )
            .accessibilityIdentifier("aiChat.failure")
        }
    }

    private func message(for failure: AIChatFailure) -> String {
        switch failure {
        case .unavailable: return L("ai.chat.error.unavailable")
        case .network: return L("ai.chat.error.network")
        case .rateLimited: return L("ai.chat.error.rate_limited")
        }
    }
}
