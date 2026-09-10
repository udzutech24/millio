//
//  AIChatComponents.swift
//  millio
//

import SwiftUI

/// Реплика диалога. Вопрос — плашкой справа, ответ — текстом слева: вложенная панель вокруг
/// длинного ответа утяжеляет экран и ничего не добавляет.
struct AIChatBubble: View {
    let role: AIChatRole
    let text: String
    /// Ответ ещё печатается — показываем курсор.
    var isStreaming: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: AppSpacing.s) {
            if role == .user { Spacer(minLength: AppSpacing.xxl) }

            if role == .assistant {
                AIChatOrb(diameter: 22, isActive: isStreaming)
                    .padding(.top, AppSpacing.xs)
            }

            Text(text + (isStreaming ? "▌" : ""))
                .font(Font.millioBodyRegular)
                .foregroundStyle(role == .user ? AppColors.textPrimary : AppColors.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, role == .user ? AppSpacing.m : .zero)
                .padding(.vertical, role == .user ? AppSpacing.s : .zero)
                .background {
                    if role == .user {
                        RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(
                                RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                            )
                    }
                }

            if role == .assistant { Spacer(minLength: AppSpacing.xxl) }
        }
    }
}

/// Плитка-подсказка на пустом экране.
struct AIChatSuggestionTile: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Font.millioCalloutRegular)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                        )
                )
        }
        .buttonStyle(.plain)
    }
}

/// Чип продолжения разговора под последним ответом.
struct AIChatChip: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(Font.millioCaption2Medium)
                .foregroundStyle(AppColors.textSecondary)
                .lineLimit(1)
                .padding(.horizontal, AppSpacing.m)
                .padding(.vertical, AppSpacing.s)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.05))
                        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.7))
                )
        }
        .buttonStyle(.plain)
    }
}

/// Карточка цифр, на которых отвечает модель: ровно то, что уходит в запрос.
/// Полосы и форматирование — общие с экраном итогов, своего форматтера у чата нет.
struct AIChatContextCard: View {
    let periodTitle: String
    let figures: AIPeriodFigures
    let currency: String
    var isAmountHidden: Bool = false

    private var peak: Double { max(figures.income, figures.expense) }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack(spacing: AppSpacing.s) {
                Text(L("ai.chat.context.title"))
                    .font(Font.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                Spacer(minLength: AppSpacing.xs)
                Text(periodTitle)
                    .font(Font.millioCaption2Medium)
                    .foregroundStyle(AppColors.textSecondary.opacity(0.7))
                    .lineLimit(1)
            }

            AIPeriodAmountBar(
                title: L("cashflow.income"),
                value: figures.income,
                share: AIPeriodSummaryFormatting.barShare(figures.income, peak: peak),
                tint: AppColors.positiveColor,
                currency: currency,
                isAmountHidden: isAmountHidden
            )

            AIPeriodAmountBar(
                title: L("cashflow.expense"),
                value: figures.expense,
                share: AIPeriodSummaryFormatting.barShare(figures.expense, peak: peak),
                tint: AppColors.negativeColor,
                currency: currency,
                isAmountHidden: isAmountHidden
            )
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinanceChromeCardBackground())
    }
}

/// Поле ввода и кнопка отправки. Фокус держится здесь же — экран пушится в стек,
/// так что через границу презентации ничего не тянем.
struct AIChatComposer: View {
    @Binding var text: String
    let isSending: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void
    /// Клавиатура сразу при появлении — вход «Спросить millio…» с дашборда.
    var autofocus: Bool = false

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.s) {
            TextField(L("ai.chat.input.placeholder"), text: $text, axis: .vertical)
                .font(Font.millioBodyRegular)
                .foregroundStyle(AppColors.textPrimary)
                .tint(FinanceScreenChrome.accentColor)
                .lineLimit(1...4)
                .focused($isFocused)
                .submitLabel(.send)
                .onSubmit { if canSend { onSend() } }
                .padding(.horizontal, AppSpacing.l)
                .padding(.vertical, AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: FinanceScreenChrome.sectionCornerRadius, style: .continuous)
                                .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                        )
                )
                .accessibilityIdentifier("aiChat.input")

            Button {
                isSending ? onStop() : onSend()
            } label: {
                Image(systemName: isSending ? "stop.fill" : "arrow.up")
                    .font(Font.millioSubheadline)
                    .foregroundStyle(isSending || canSend ? Color.black : AppColors.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(
                                isSending || canSend
                                    ? AnyShapeStyle(
                                        LinearGradient(
                                            colors: AppColors.financesGradient,
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    : AnyShapeStyle(Color.white.opacity(0.08))
                            )
                    )
            }
            .buttonStyle(.plain)
            .disabled(!isSending && !canSend)
            .accessibilityLabel(isSending ? L("ai.chat.stop") : L("ai.chat.send"))
            .accessibilityIdentifier("aiChat.send")
        }
        .padding(.horizontal, AppSpacing.l)
        .padding(.vertical, AppSpacing.m)
        .background(.ultraThinMaterial)
        .autofocusAfterPresentation($isFocused, isEnabled: autofocus)
    }
}
