import SwiftUI

struct DepositDetailSection: View {
    let presentation: DepositDetailPresentation
    let accountName: String
    var taxPresentation: DepositTaxPresentation? = nil
    let onAction: (DepositDetailAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.l) {
            hero
            if !presentation.actions.isEmpty { actions }
            if presentation.state == .incomplete { incompleteNotice }
            if let taxPresentation { taxSection(taxPresentation) }
        }
        .accessibilityElement(children: .contain)
    }

    private func taxSection(_ tax: DepositTaxPresentation) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(String(format: L("accounts_core.deposit.tax.title"), tax.year)).font(.millioBodySemibold)
            if let result = tax.result, tax.isComplete {
                Text(String(format: L("accounts_core.deposit.tax.estimate"), NSDecimalNumber(decimal: result.totalTaxRUB).stringValue))
            } else {
                Text(L("accounts_core.deposit.tax.unavailable"))
            }
            Text(L("accounts_core.deposit.tax.disclaimer"))
                .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            HStack {
                Label(stateTitle, systemImage: stateIcon)
                    .font(.millioHeadline)
                Spacer(minLength: AppSpacing.s)
            }
            .foregroundStyle(.white.opacity(0.82))

            if let progress = presentation.snapshot.progress {
                progressView(progress)
            }

            amount(presentation.snapshot.currentBalance, label: L("accounts_core.deposit.detail.balance"), prominent: true)

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: AppSpacing.s) {
                    metricCard(presentation.snapshot.confirmedInterest, label: L("accounts_core.deposit.detail.earned"))
                    metricCard(presentation.snapshot.futureInterest, label: L("accounts_core.deposit.detail.estimated"))
                }
                VStack(spacing: AppSpacing.s) {
                    metricCard(presentation.snapshot.confirmedInterest, label: L("accounts_core.deposit.detail.earned"))
                    metricCard(presentation.snapshot.futureInterest, label: L("accounts_core.deposit.detail.estimated"))
                }
            }

            if let accrual = presentation.snapshot.nextAccrual {
                infoRow(L("accounts_core.deposit.detail.next_accrual"), value: dateAmount(accrual))
            }
            if let maturity = presentation.snapshot.maturityDate {
                infoRow(L("accounts_core.deposit.detail.maturity"), value: "\(maturity.formatted(date: .abbreviated, time: .omitted)) · \(amountText(presentation.snapshot.maturityAmount))")
            }
        }
        .padding(AppSpacing.l)
        .background(
            LinearGradient(
                colors: [Color(hex: "123F7A"), Color(hex: "0D6B78")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.xl, style: .continuous))
        )
        .accessibilityLabel("\(accountName), \(stateTitle)")
    }

    private var actions: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: AppSpacing.s)], spacing: AppSpacing.s) {
            ForEach(presentation.actions, id: \.self) { action in
                Button { onAction(action) } label: {
                    Label(actionTitle(action), systemImage: actionIcon(action))
                        .font(.millioBodySemibold)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, AppSpacing.s)
                        .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
                }
                .buttonStyle(.plain)
                .foregroundStyle(action == .earlyClose || action == .archive ? AppColors.error : AppColors.textPrimary)
            }
        }
    }

    private var incompleteNotice: some View {
        Label(L("accounts_core.deposit.detail.incomplete"), systemImage: "exclamationmark.triangle.fill")
            .font(.millioCalloutRegular)
            .foregroundStyle(AppColors.warning)
    }

    private func amount(_ amount: DepositAmount, label: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label).font(.millioCaptionRegular).foregroundStyle(.white.opacity(0.68))
            Text(amountText(amount))
                .font(prominent ? .system(size: 28, weight: .bold) : .millioHeadline)
                .foregroundStyle(.white)
                .minimumScaleFactor(0.72)
                .lineLimit(1)
            if amount.provenance == .estimated {
                Text(L("accounts_core.deposit.detail.forecast"))
                    .font(.millioCaptionRegular)
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricCard(_ amount: DepositAmount, label: String) -> some View {
        self.amount(amount, label: label)
            .padding(AppSpacing.m)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: AppSpacing.m, style: .continuous))
    }

    private func progressView(_ progress: Decimal) -> some View {
        let clamped = min(max(NSDecimalNumber(decimal: progress).doubleValue, 0), 1)
        return VStack(spacing: AppSpacing.xs) {
            HStack {
                Text(L("accounts_core.deposit.detail.term_progress"))
                Spacer()
                Text(clamped.formatted(.percent.precision(.fractionLength(0))))
                    .font(.millioCalloutSemibold)
            }
            .font(.millioCalloutRegular)
            ProgressView(value: clamped)
                .tint(.white)
        }
        .foregroundStyle(.white.opacity(0.78))
    }

    private func infoRow(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text(label)
                .font(.millioCalloutRegular)
                .foregroundStyle(.white.opacity(0.66))
            Text(value)
                .font(.millioBodySemibold)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func amountText(_ amount: DepositAmount) -> String {
        guard let value = amount.value else { return L("accounts_core.deposit.detail.unavailable") }
        return DepositAmountTextFormatter.string(
            value,
            currency: presentation.snapshot.currency,
            locale: AppLocalization.currentAppLocale
        )
    }

    private func dateAmount(_ accrual: DepositAccrual) -> String {
        "\(accrual.date.formatted(date: .abbreviated, time: .omitted)) · \(amountText(accrual.amount))"
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

    private var stateIcon: String {
        switch presentation.state {
        case .normal, .savings: "banknote.fill"
        case .dueSoon: "clock.fill"
        case .maturedNeedsAction: "checkmark.circle.fill"
        case .archived: "archivebox.fill"
        case .incomplete: "exclamationmark.triangle.fill"
        }
    }

    private func actionTitle(_ action: DepositDetailAction) -> String {
        switch action {
        case .topUp: L("accounts_core.deposit.action.top_up")
        case .editTerms: L("accounts_core.deposit.action.edit_terms")
        case .earlyClose: L("accounts_core.detail.deposit.action.early_close")
        case .withdrawAtMaturity: L("accounts_core.deposit.action.withdraw_maturity")
        case .archive: L("accounts_core.detail.action.delete")
        }
    }

    private func actionIcon(_ action: DepositDetailAction) -> String {
        switch action {
        case .topUp: "plus.circle.fill"
        case .editTerms: "pencil"
        case .earlyClose: "xmark.circle.fill"
        case .withdrawAtMaturity: "arrow.right.circle.fill"
        case .archive: "archivebox.fill"
        }
    }
}

enum DepositAmountTextFormatter {
    static func string(_ value: Decimal, currency: String, locale: Locale) -> String {
        let number = value.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(0...2))
        )
        return "\(number) \(currency)"
    }
}
