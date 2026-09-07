//
//  AppliedPlannedNoticeSheet.swift
//  millio
//
//  Лист снизу «Пока вас не было»: что применилось автоматически, пока пользователь не смотрел.
//  Фаза 3 плана plans/2026-09-05__planned-operations-applied-notice.md.
//
//  Только информирование: ни одной кнопки, меняющей деньги. Откат вынесен в отдельную задачу,
//  и до неё лист не должен намекать на действие.
//

import SwiftUI

// MARK: - AppliedPlannedNoticeSheet

/// Обёртка презентации. Отдельно от содержимого, чтобы содержимое можно было отрисовать
/// без модификаторов листа — в превью и в снимке для гейта.
struct AppliedPlannedNoticeSheet: View {
    let digest: AppliedPlannedDigest

    var body: some View {
        AppliedPlannedNoticeContent(summary: AppliedPlannedNoticeSummary(digest: digest))
            // Фиксированной высоты нет намеренно: содержимое растёт от объёма (до 50 строк
            // деталей — это тысячи точек), и любой `.fraction` обрезал бы список.
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }
}

// MARK: - AppliedPlannedNoticeContent

/// Шасси листа: фон, скролл и кнопка закрытия. Содержимое живёт отдельным `View`, потому что
/// `ImageRenderer` не раскладывает содержимое `ScrollView` — а проверка «ничего не обрезано»
/// снимается только рендером колонки целиком.
struct AppliedPlannedNoticeContent: View {

    let summary: AppliedPlannedNoticeSummary
    let isInitiallyExpanded: Bool

    @Environment(\.dismiss) private var dismiss

    init(summary: AppliedPlannedNoticeSummary, isExpanded: Bool = false) {
        self.summary = summary
        self.isInitiallyExpanded = isExpanded
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                ScrollView {
                    AppliedPlannedNoticeColumn(summary: summary, isExpanded: isInitiallyExpanded)
                }

                dismissButton
            }
        }
    }

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Text(L("cashflow.applied_notice.dismiss"))
                .font(.millioHeadline)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.vertical, AppSpacing.m)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous)
                        .fill(AppColors.cardBoxBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous)
                                .stroke(AppColors.cardBoxBorder, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.s)
        .padding(.bottom, AppSpacing.l)
    }
}

// MARK: - AppliedPlannedNoticeColumn

/// Прокручиваемое содержимое сводки. Своей высоты не задаёт и ничего не обрезает: ни одного
/// `lineLimit` и ни одного `frame(height:)` — длинный текст переносится, колонка растёт,
/// а прокрутку даёт шасси.
struct AppliedPlannedNoticeColumn: View {

    let summary: AppliedPlannedNoticeSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isExpanded: Bool

    /// Фаза дизеринга шапки: 0 на появлении, 1 в осевшем состоянии.
    @State private var appearPhase: Double = 0

    /// Смена значения — момент вибрации для `.sensoryFeedback`.
    @State private var hapticTick = false

    /// `isExpanded` в инициализаторе — вход для превью и снимка: в приложении лист всегда
    /// открывается свёрнутым.
    init(summary: AppliedPlannedNoticeSummary, isExpanded: Bool = false) {
        self.summary = summary
        _isExpanded = State(initialValue: isExpanded)
    }

    private var appearance: AppliedPlannedNoticeAppearancePlan {
        AppliedPlannedNoticeAppearancePlan.make(reduceMotion: reduceMotion)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            titleBlock
            totalsCard
            if !summary.details.isEmpty {
                detailsSection
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.l)
        .padding(.top, AppSpacing.l)
        .padding(.bottom, AppSpacing.xl)
        .onAppear { playAppearance() }
        // Декларативный отклик вместо UIKit-генератора: он привязан к смене состояния, сам
        // уважает системные настройки и не требует ручного prepare/удержания генератора.
        .sensoryFeedback(trigger: hapticTick) { _, _ in
            switch appearance.haptic {
            case .softImpact: return .impact(flexibility: .soft, intensity: 0.7)
            case nil: return nil
            }
        }
    }

    /// Дизеринг обязан проявиться, а не появиться готовым: без движения фазы шейдер читается
    /// просто как ещё одна заливка. При Reduce Motion фаза сразу конечная и вибрации нет.
    private func playAppearance() {
        guard appearance.isDitherEnabled else {
            appearPhase = 1
            return
        }
        withAnimation(AppAnimation.springGentle) { appearPhase = 1 }
        if appearance.haptic != nil { hapticTick.toggle() }
    }

    // MARK: - Заголовок

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("cashflow.applied_notice.title \(summary.totalCount)"))
                .font(.millioTitle3)
                .foregroundStyle(AppColors.textPrimary)

            Text(L("cashflow.applied_notice.subtitle"))
                .font(.millioCalloutRegular)
                .foregroundStyle(AppColors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.l)
        .background(headerBackground)
    }

    /// Эффект живёт только в шапке: дизеринг под колонкой сумм мешал бы их читать, а на дашборде
    /// ему нечего сообщать — сводка показывается ровно один раз на цикл применения.
    @ViewBuilder
    private var headerBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous)
        if appearance.isDitherEnabled {
            // Белая заливка — маска: цвет каждого пикселя считает шейдер, от фигуры ему нужна
            // только альфа, дающая сглаженные скругления.
            shape
                .fill(.white)
                .ditheredGradient(phase: appearPhase)
        } else {
            shape.fill(
                LinearGradient(
                    colors: AppColors.cashflowGradient,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
    }

    // MARK: - Итоги по валютам

    private var totalsCard: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            Text(L("cashflow.applied_notice.totals"))
                .font(.millioCaption)
                .foregroundStyle(AppColors.textTertiary)
                .textCase(.uppercase)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(summary.currencyLines) { line in
                currencyRow(line)
            }

            if let counts = countsText {
                Text(counts)
                    .font(.millioCalloutRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(AppSpacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func currencyRow(_ line: AppliedPlannedNoticeSummary.CurrencyLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.m) {
            Text(line.currencyCode)
                .font(.millioCallout)
                .foregroundStyle(AppColors.textSecondary)

            Spacer(minLength: AppSpacing.s)

            Text(AppliedPlannedNoticeAmountFormat.signedAmount(line.net, currencyCode: line.currencyCode))
                .font(.millioTitle3)
                .foregroundStyle(amountColor(for: line.net))
        }
        // Переносим, а не обрезаем: длинная сумма в редкой валюте уедет на вторую строку,
        // но не превратится в «…».
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Начисления и списания — общие по всей сводке, не по каждой валюте: журнал per-currency
    /// счётчиков не хранит, а восстанавливать их по обрезанным деталям значит соврать.
    private var countsText: String? {
        var parts: [String] = []
        if summary.incomeCount > 0 {
            parts.append(L("cashflow.applied_notice.income_count \(summary.incomeCount)"))
        }
        if summary.expenseCount > 0 {
            parts.append(L("cashflow.applied_notice.expense_count \(summary.expenseCount)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Список деталей

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            disclosureButton

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(summary.details.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider().overlay(AppColors.cardBoxBorder)
                        }
                        detailRow(entry)
                    }

                    if summary.truncatedCount > 0 {
                        Divider().overlay(AppColors.cardBoxBorder)
                        Text(L("cashflow.applied_notice.more \(summary.truncatedCount)"))
                            .font(.millioCalloutRegular)
                            .foregroundStyle(AppColors.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, AppSpacing.m)
                    }
                }
                .padding(.horizontal, AppSpacing.l)
                .background(cardBackground)
                .transition(.opacity)
            }
        }
    }

    private var disclosureButton: some View {
        Button {
            withAnimation(AppAnimation.spring) { isExpanded.toggle() }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.s) {
                Text(
                    isExpanded
                        ? L("cashflow.applied_notice.hide_details")
                        : L("cashflow.applied_notice.show_details")
                )
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppSpacing.s)

                Image(systemName: "chevron.down")
                    .font(.millioCaption)
                    .foregroundStyle(AppColors.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func detailRow(_ entry: AppliedPlannedEntry) -> some View {
        let info = VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(entry.title)
                .font(.millioSubheadline)
                .foregroundStyle(AppColors.textPrimary)

            Text(entry.accountName)
                .font(.millioCaptionRegular)
                .foregroundStyle(AppColors.textSecondary)

            if entry.kind == .depositInterest {
                depositInterestNote
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)

        let amount = Text(
            AppliedPlannedNoticeAmountFormat.signedAmount(entry.amount, currencyCode: entry.currencyCode)
        )
        .font(.millioSubheadline)
        .foregroundStyle(amountColor(for: entry.amount))
        .fixedSize(horizontal: false, vertical: true)

        HStack(alignment: .top, spacing: AppSpacing.m) {
            info
            amount
        }
        .padding(.vertical, AppSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Проценты по вкладу — единственный вид записей, который пользователь не планировал сам.
    /// Помечаем их как справку, чтобы строка не читалась как ещё одна его операция.
    private var depositInterestNote: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
            Image(systemName: "percent")
            Text(L("cashflow.applied_notice.deposit_interest_note"))
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.millioCaption2Regular)
        .foregroundStyle(AppColors.textTertiary)
    }

    // MARK: - Общее

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous)
            .fill(AppColors.cardBoxBackground)
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.l, style: .continuous)
                    .stroke(AppColors.cardBoxBorder, lineWidth: 1)
            )
    }

    private func amountColor(for amount: Decimal) -> Color {
        if amount > 0 { return AppColors.positiveColor }
        if amount < 0 { return AppColors.negativeColor }
        return AppColors.textPrimary
    }
}

// MARK: - Превью

#if DEBUG
/// Фикстура превью: 62 применения при потолке деталей 50 — состояние с «и ещё N», до которого
/// вручную не доберёшься, и именно на нём снимался гейт Ф3.
private func appliedPlannedNoticePreviewSummary() -> AppliedPlannedNoticeSummary {
    var digest = AppliedPlannedDigest()
    let titles = ["Аренда квартиры", "Подписка на хранилище", "Зарплата", "Коммунальные платежи"]
    let accounts = ["Основной счёт", "Накопительный счёт", "Карта для подписок", "Вклад «Максимальный доход»"]
    for index in 0..<62 {
        let isInterest = index % 7 == 0
        digest.accumulate(
            AppliedPlannedEntry(
                title: isInterest ? "Проценты по вкладу" : titles[index % titles.count],
                accountName: accounts[index % accounts.count],
                amount: isInterest
                    ? Decimal(index) + Decimal(string: "0.37")!
                    : (index.isMultiple(of: 2) ? Decimal(1_500 + index * 137) : Decimal(-(940 + index * 53))),
                currencyCode: index % 11 == 0 ? "USD" : "RUB",
                appliedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                kind: isInterest ? .depositInterest : (index.isMultiple(of: 3) ? .recurring : .scheduled)
            )
        )
    }
    return AppliedPlannedNoticeSummary(digest: digest)
}

#Preview("Сводка — свёрнутая") {
    AppliedPlannedNoticeContent(summary: appliedPlannedNoticePreviewSummary())
}

#Preview("Сводка — список раскрыт") {
    AppliedPlannedNoticeContent(summary: appliedPlannedNoticePreviewSummary(), isExpanded: true)
}
#endif
