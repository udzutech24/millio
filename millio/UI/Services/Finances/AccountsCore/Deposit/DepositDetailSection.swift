import SwiftUI

/// Содержимое единой hero-карточки вклада (баланс → статус+прогресс → метрики → условия).
/// Рисуется ВНУТРИ `AccountHeroCardView` как `customContent` — карточка-носитель (градиент,
/// скругления, паддинги) остаётся общей для всех типов счетов, у вклада меняется только начинка:
/// identity-строка (имя/бейдж/иконка) вклада не нужна — оно уже в navigation title.
struct DepositHeroContent: View {
    let presentation: DepositDetailPresentation
    /// Дата открытия вклада — нужна только для строки под шкалой срока («начало · окончание»);
    /// в `DepositPresentationSnapshot` её нет (снапшот — чистый расчёт, а не карточка счёта).
    let openingDate: Date
    /// Условия вклада для итоговой строки («3,6 % годовых · пополняемый · капитализация…»).
    /// `nil` у `incomplete`-вклада — условия ещё не заполнены.
    let meta: DepositMeta?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            balanceBlock
            hairline
            statusBlock
            hairline
            metricsRow
            if let summaryLine {
                hairline
                Text(summaryLine)
                    .font(.millioCaptionRegular)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var hairline: some View {
        Rectangle().fill(.white.opacity(0.16)).frame(height: 1)
    }

    private var balanceBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(L("accounts_core.deposit.detail.balance"))
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.68))
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.xs) {
                Text(amountText(presentation.snapshot.currentBalance))
                    .font(.millioTitle)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
            if let confirmed = presentation.snapshot.confirmedInterest.value, confirmed > 0 {
                Text(String(
                    format: L("accounts_core.deposit.detail.balance_includes_accrued_format"),
                    amountText(presentation.snapshot.confirmedInterest)
                ))
                .font(.millioCaptionRegular)
                .foregroundStyle(.white.opacity(0.62))
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: AppSpacing.s) {
            HStack {
                Circle().fill(statusDotColor).frame(width: 8, height: 8)
                Text(stateTitle)
                    .font(.millioCalloutRegular)
                Spacer(minLength: AppSpacing.s)
                if presentation.state == .archived {
                    Text(L("accounts_core.deposit.detail.status.closed"))
                        .font(.millioCalloutSemibold)
                } else if let daysRemaining = presentation.snapshot.daysRemaining, daysRemaining >= 0 {
                    Text(L("accounts_core.deposit.detail.days_remaining \(daysRemaining)"))
                        .font(.millioCalloutSemibold)
                }
            }
            .foregroundStyle(.white.opacity(0.9))

            if let progress = presentation.snapshot.progress {
                AccountHeroProgressBar(progress: progress)
                HStack {
                    Text(openingDate.formatted(date: .abbreviated, time: .omitted))
                    Spacer()
                    if let maturityDate = presentation.snapshot.maturityDate {
                        Text(maturityDate.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.millioMicro)
                .foregroundStyle(.white.opacity(0.58))
            }
        }
    }

    private var statusDotColor: Color {
        switch presentation.state {
        case .dueSoon, .maturedNeedsAction: AppColors.warning
        case .archived: .white.opacity(0.5)
        default: .white
        }
    }

    @ViewBuilder
    private var metricsRow: some View {
        if presentation.state == .archived {
            metricCard(presentation.snapshot.confirmedInterest, label: L("accounts_core.deposit.detail.received_over_term"))
        } else {
            let next = presentation.snapshot.nextAccrual
            let maturity = presentation.snapshot.maturityAmount.value != nil ? presentation.snapshot.maturityAmount : nil
            if next != nil || maturity != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: AppSpacing.s) { metricTiles(next: next, maturity: maturity) }
                    VStack(spacing: AppSpacing.s) { metricTiles(next: next, maturity: maturity) }
                }
            }
        }
    }

    @ViewBuilder
    private func metricTiles(next: DepositAccrual?, maturity: DepositAmount?) -> some View {
        if let next { nextAccrualMetric(next) }
        if let maturity { maturityMetric(maturity) }
    }

    private func nextAccrualMetric(_ accrual: DepositAccrual) -> some View {
        AccountHeroMetricTile(
            title: L("accounts_core.deposit.detail.next_accrual"),
            value: "+\(amountText(accrual.amount))",
            caption: accrual.date.formatted(date: .abbreviated, time: .omitted)
        )
    }

    private func maturityMetric(_ amount: DepositAmount) -> some View {
        AccountHeroMetricTile(
            title: L("accounts_core.deposit.detail.maturity_metric_label"),
            value: amountText(amount),
            caption: L("accounts_core.deposit.detail.forecast")
        )
    }

    private func metricCard(_ amount: DepositAmount, label: String) -> some View {
        AccountHeroMetricTile(title: label, value: amountText(amount))
    }

    /// Итоговая строка условий вклада. Нет `meta` (вклад `incomplete`) или вклад закрыт — строка не
    /// нужна: у закрытого вклада условия уже не действуют, у неполного — их ещё нет.
    private var summaryLine: String? {
        guard let meta, presentation.state != .archived, presentation.state != .incomplete else { return nil }
        let rate = String(format: L("accounts_core.deposit.detail.rate_yearly_format"), NSDecimalNumber(decimal: meta.rate).doubleValue)
        let topUp = meta.allowsTopUp
            ? L("accounts_core.detail.deposit.badge.top_up_allowed")
            : L("accounts_core.detail.deposit.badge.top_up_denied")
        let capitalization = String(format: L("accounts_core.deposit.detail.capitalization_format"), capitalizationTitle(meta.capitalization))
        return [rate, topUp, capitalization].joined(separator: " · ")
    }

    private func capitalizationTitle(_ capitalization: AccountDepositCapitalization) -> String {
        switch capitalization {
        case .none: L("accounts_core.deposit_form.capitalization.none")
        case .daily: L("accounts_core.deposit_form.capitalization.daily")
        case .monthly: L("accounts_core.deposit_form.capitalization.monthly")
        case .quarterly: L("accounts_core.deposit_form.capitalization.quarterly")
        case .customDays: L("accounts_core.deposit_form.capitalization.custom")
        }
    }

    private func amountText(_ amount: DepositAmount) -> String {
        guard let value = amount.value else { return L("accounts_core.deposit.detail.unavailable") }
        return DepositAmountTextFormatter.string(
            value,
            currency: presentation.snapshot.currency,
            symbol: currencySymbol,
            locale: AppLocalization.currentAppLocale
        )
    }

    /// Один символ валюты везде на карточке ($, не "$" и "USD" вперемешку) — тот же резолвер,
    /// что использует общий hero счетов (`AccountHeroPresentation`).
    private var currencySymbol: String {
        MonetaCurrency(rawValue: presentation.snapshot.currency)?.symbol ?? presentation.snapshot.currency
    }

    private var stateTitle: String {
        switch presentation.state {
        case .normal: L("accounts_core.deposit.state.active")
        case .savings: L("accounts_core.deposit.state.savings")
        case .dueSoon: L("accounts_core.deposit.state.due_soon")
        case .maturedNeedsAction: L("accounts_core.deposit.state.matured")
        case .archived: L("accounts_core.deposit.state.archived")
        case .incomplete: L("accounts_core.deposit.state.incomplete")
        }
    }
}

/// То, что раньше жило ПОД hero-карточкой вклада: быстрые действия, предупреждение о неполных
/// данных и налоговая плашка. Сам hero (баланс/статус/метрики) теперь рисует `DepositHeroContent`
/// внутри общего `AccountHeroCardView` — см. `AccountDetailView.body`.
struct DepositDetailSection: View {
    let presentation: DepositDetailPresentation
    var taxPresentation: DepositTaxPresentation? = nil
    let onAction: (DepositDetailAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            if !presentation.actions.isEmpty { actions }
            if presentation.state == .incomplete { incompleteNotice }
            if let taxPresentation { taxSection(taxPresentation) }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Налог

    private func taxSection(_ tax: DepositTaxPresentation) -> some View {
        AccountDetailPlaqueSection(
            title: String(format: L("accounts_core.deposit.tax.title"), tax.year),
            caption: tax.isComplete ? L("accounts_core.deposit.tax.caption_estimate") : nil
        ) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                if let result = tax.result, tax.isComplete {
                    Text(String(format: L("accounts_core.deposit.tax.estimate"), NSDecimalNumber(decimal: result.totalTaxRUB).stringValue))
                        .font(.millioBodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    // Дисклеймер уместен только рядом с реально посчитанной суммой — иначе он звучит
                    // как предупреждение о несуществующей цифре.
                    Text(L("accounts_core.deposit.tax.disclaimer"))
                        .font(.millioCaptionRegular)
                        .foregroundStyle(AppColors.textSecondary)
                } else {
                    Text(L("accounts_core.deposit.tax.empty.title"))
                        .font(.millioBodySemibold)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(L("accounts_core.deposit.tax.empty.message"))
                        .font(.millioCalloutRegular)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Действия

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.s)], spacing: AppSpacing.s) {
            ForEach(primaryActions, id: \.self) { action in
                Button { onAction(action) } label: {
                    Label(actionTitle(action), systemImage: actionIcon(action))
                        .font(.millioBodySemibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, AppSpacing.s)
                        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(actionBackground(action)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(actionForeground(action))
            }
        }
    }

    /// «Пополнить» — заливная акцентная (это основной путь пользователя на этом экране), «Изменить
    /// баланс» — тише (контурная логика через полупрозрачную заливку), чтобы кнопки не читались как
    /// два равнозначных действия.
    private func actionBackground(_ action: DepositDetailAction) -> Color {
        action == .topUp ? AppColors.positiveColor : AppColors.iconBackground
    }

    private func actionForeground(_ action: DepositDetailAction) -> Color {
        if action == .earlyClose || action == .archive { return AppColors.error }
        return action == .topUp ? .white : AppColors.textPrimary
    }

    /// Frequent money operations stay discoverable. Lifecycle and destructive actions live in the
    /// detail toolbar, where `AccountDetailView` preserves their confirmations.
    private var primaryActions: [DepositDetailAction] {
        presentation.actions.filter { $0 == .topUp || $0 == .adjustBalance }
    }

    private var incompleteNotice: some View {
        Label(L("accounts_core.deposit.detail.incomplete"), systemImage: "exclamationmark.triangle.fill")
            .font(.millioCalloutRegular)
            .foregroundStyle(AppColors.warning)
    }

    private func actionTitle(_ action: DepositDetailAction) -> String {
        switch action {
        case .topUp: L("accounts_core.deposit.action.top_up")
        case .adjustBalance: L("accounts_core.detail.action.adjust_balance")
        case .editTerms: L("accounts_core.deposit.action.edit_terms")
        case .earlyClose: L("accounts_core.detail.deposit.action.early_close")
        case .withdrawAtMaturity: L("accounts_core.deposit.action.withdraw_maturity")
        case .archive: L("accounts_core.detail.action.delete")
        }
    }

    private func actionIcon(_ action: DepositDetailAction) -> String {
        switch action {
        case .topUp: "plus.circle.fill"
        case .adjustBalance: "slider.horizontal.3"
        case .editTerms: "pencil"
        case .earlyClose: "xmark.circle.fill"
        case .withdrawAtMaturity: "arrow.right.circle.fill"
        case .archive: "archivebox.fill"
        }
    }
}

enum DepositAmountTextFormatter {
    /// `symbol` — то, что реально показываем ("$"); `currency` остаётся фолбэком для старых
    /// вызовов (превью формы), где символа под рукой ещё нет.
    static func string(_ value: Decimal, currency: String, symbol: String? = nil, locale: Locale) -> String {
        let number = value.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
        return "\(number) \(symbol ?? currency)"
    }
}
