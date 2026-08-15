import SwiftUI

struct CreditCardDetailSection: View {
    let account: Account
    let rawBalance: Decimal

    private var snapshot: CreditCardFinancialSnapshot? {
        guard let limit = account.cardMeta?.creditLimit else { return nil }
        return CreditCardFinancialContract.snapshot(
            rawAvailableBalance: rawBalance,
            creditLimit: limit,
            events: account.events ?? []
        )
    }

    private var paymentStatus: CreditCardPaymentStatus? {
        guard let settings = CreditCardPaymentSettingsStore().load(accountID: account.id) else { return nil }
        return CreditCardPaymentPolicy.status(
            settings: settings, graceDays: account.cardMeta?.graceDays, now: Date(), calendar: .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(account.name).font(.millioHeadline)
                if let identityLine { Text(identityLine).font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary) }
                Text(displayAmount(snapshot?.debt ?? 0))
                    .font(.millioTitle)
                    .foregroundStyle((snapshot?.debt ?? 0) > 0 ? AppColors.error : AppColors.textPrimary)
                    .accessibilityLabel("Current debt \(displayAmount(snapshot?.debt ?? 0))")
                if let overpayment = snapshot?.overpayment, overpayment > 0 {
                    Label("Overpayment \(displayAmount(overpayment))", systemImage: "checkmark.circle.fill")
                        .font(.millioCalloutRegular).foregroundStyle(AppColors.toggleOnGreen)
                }
                if !account.includeInTotal {
                    Label(L("accounts_core.detail.total.excluded"), systemImage: "sum")
                        .font(.millioCaptionRegular).foregroundStyle(AppColors.textSecondary)
                }
            }
            .padding(AppSpacing.m)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.m))

            if let snapshot {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    adaptiveRow("Available limit", value: displayAmount(snapshot.availableLimit))
                    adaptiveRow("Credit limit", value: displayAmount(snapshot.creditLimit))
                    adaptiveRow("Utilization", value: percent(snapshot.utilization))
                    ProgressView(value: min(max(Double(truncating: snapshot.utilization as NSNumber), 0), 1))
                        .tint(snapshot.isOverLimit ? AppColors.error : AppColors.brandPrimary)
                        .accessibilityLabel("Credit utilization")
                        .accessibilityValue(percent(snapshot.utilization))
                    if snapshot.accruedInterest > 0 { adaptiveRow("Accrued interest", value: displayAmount(snapshot.accruedInterest)) }
                    if snapshot.accruedFees > 0 { adaptiveRow("Fees", value: displayAmount(snapshot.accruedFees)) }
                }
                .padding(AppSpacing.m)
                .background(RoundedRectangle(cornerRadius: AppSpacing.m).fill(AppColors.iconBackground))
            } else {
                ContentUnavailableView("Credit terms unavailable", systemImage: "creditcard.trianglebadge.exclamationmark")
            }

            if let paymentStatus {
                VStack(alignment: .leading, spacing: AppSpacing.s) {
                    Label(paymentStatus.isOverdue ? "Платёж просрочен" : "Ближайший платёж", systemImage: paymentStatus.isOverdue ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                        .font(.millioHeadline)
                        .foregroundStyle(paymentStatus.isOverdue ? AppColors.error : AppColors.textPrimary)
                    adaptiveRow("Дата платежа", value: paymentStatus.dueDate.formatted(date: .long, time: .omitted))
                    Text(paymentStatus.isOverdue ? "Просрочено на \(-paymentStatus.daysRemaining) дн." : "Осталось \(paymentStatus.daysRemaining) дн.")
                        .font(.millioCalloutRegular).foregroundStyle(AppColors.textSecondary)
                }
                .padding(AppSpacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.m))
            } else {
                ContentUnavailableView("Дата платежа не настроена", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }

    private var identityLine: String? {
        var parts: [String] = []
        if let bank = account.cardMeta?.bank, !bank.isEmpty { parts.append(Bank(rawValue: bank)?.displayName ?? bank) }
        if let last4 = account.cardMeta?.last4, !last4.isEmpty { parts.append("•••• \(last4)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func adaptiveRow(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(title).foregroundStyle(AppColors.textSecondary); Spacer(); Text(value).font(.millioBodySemibold) }
            VStack(alignment: .leading, spacing: 3) { Text(title).foregroundStyle(AppColors.textSecondary); Text(value).font(.millioBodySemibold) }
        }
        .accessibilityElement(children: .combine)
    }

    private func displayAmount(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        return "\(formatter.string(from: value as NSNumber) ?? "0") \(account.currency)"
    }

    private func percent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.maximumFractionDigits = 1
        return formatter.string(from: value as NSNumber) ?? "0%"
    }
}
