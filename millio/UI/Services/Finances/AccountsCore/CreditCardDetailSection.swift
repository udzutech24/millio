import EventKitUI
import SwiftUI

struct CreditCardDetailSection: View {
    let account: Account
    let rawBalance: Decimal
    @Environment(ToastCenter.self) private var toastCenter
    @State private var showCalendarExportConfirmation = false
    @State private var calendarExportPayload: AppleCalendarEventExportPayload?
    @State private var isCalendarExportInProgress = false
    @State private var calendarEventStore = AppleCalendarEventStore()

    private var snapshot: CreditCardFinancialSnapshot? {
        guard let limit = account.cardMeta?.creditLimit else { return nil }
        return CreditCardFinancialContract.snapshot(
            rawAvailableBalance: rawBalance,
            creditLimit: limit,
            events: account.events ?? []
        )
    }

    private var paymentStatus: CreditCardPaymentStatus? {
        guard let settings = paymentSettings else { return nil }
        return CreditCardPaymentPolicy.status(
            settings: settings, graceDays: account.cardMeta?.graceDays, now: Date(), calendar: .current
        )
    }

    private var paymentSettings: CreditCardPaymentSettings? {
        CreditCardPaymentSettingsStore().load(accountID: account.id)
    }

    private var canExportPaymentToCalendar: Bool {
        guard let paymentStatus, !paymentStatus.isOverdue else { return false }
        return AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: paymentStatus.dueDate,
            now: Date(),
            calendar: .current
        )
    }

    var body: some View {
        // Ф3: имя, долг, `•• last4` и статус «не в тотале» рисует общий `AccountHeroCardView`
        // над секцией — здесь остались только метрики, специфичные для кредитки.
        VStack(alignment: .leading, spacing: AppSpacing.m) {
            if let overpayment = snapshot?.overpayment, overpayment > 0 {
                Label("Overpayment \(displayAmount(overpayment))", systemImage: "checkmark.circle.fill")
                    .font(.millioCalloutRegular).foregroundStyle(AppColors.toggleOnGreen)
            }

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
                    if canExportPaymentToCalendar {
                        Button {
                            showCalendarExportConfirmation = true
                        } label: {
                            Label(
                                L("credit_card.calendar_export.action", defaultValue: "Add to Calendar"),
                                systemImage: "calendar.badge.plus"
                            )
                            .font(.millioBodySemibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, AppSpacing.s)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppColors.brandPrimary)
                        .background(
                            RoundedRectangle(cornerRadius: AppSpacing.s, style: .continuous)
                                .fill(AppColors.brandPrimary.opacity(0.14))
                        )
                        .disabled(isCalendarExportInProgress)
                        .accessibilityHint(L(
                            "credit_card.calendar_export.action.hint",
                            defaultValue: "Opens Apple Calendar to add this payment"
                        ))
                    }
                }
                .padding(AppSpacing.m)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: AppSpacing.m))
            } else {
                ContentUnavailableView("Дата платежа не настроена", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .confirmationDialog(
            L("credit_card.calendar_export.confirmation.title", defaultValue: "Add payment to Calendar?"),
            isPresented: $showCalendarExportConfirmation,
            titleVisibility: .visible
        ) {
            Button(L("credit_card.calendar_export.confirmation.action", defaultValue: "Continue")) {
                beginCalendarExport()
            }
            Button(L("cashflow.common.cancel"), role: .cancel) {}
        } message: {
            Text(L(
                "credit_card.calendar_export.confirmation.message",
                defaultValue: "Millio will open Apple Calendar. Later changes to this payment will not update the exported event."
            ))
        }
        .sheet(item: $calendarExportPayload) { payload in
            AppleCalendarEventEditorSheet(eventStore: calendarEventStore, payload: payload) { action in
                calendarExportPayload = nil
                if action == .saved {
                    toastCenter.show(message: L(
                        "credit_card.calendar_export.saved",
                        defaultValue: "Payment added to Calendar"
                    ))
                }
            }
        }
    }

    private func beginCalendarExport() {
        guard !isCalendarExportInProgress,
              let paymentStatus,
              let paymentSettings,
              canExportPaymentToCalendar,
              let payload = CreditCardCalendarPaymentExport().makePayload(
                  cardName: account.name,
                  paymentStatus: paymentStatus,
                  settings: paymentSettings,
                  minimumPayment: account.cardMeta?.minPayment,
                  currency: account.currency
              ) else {
            toastCenter.show(message: L(
                "credit_card.calendar_export.unavailable",
                defaultValue: "Calendar event could not be prepared"
            ))
            return
        }

        isCalendarExportInProgress = true
        Task { @MainActor in
            let authorizer = AppleCalendarEventExportAuthorizer(eventStore: calendarEventStore)
            let state = await authorizer.authorizeForExport()
            isCalendarExportInProgress = false
            switch state {
            case .granted:
                calendarExportPayload = payload
            case .denied, .restricted:
                toastCenter.show(message: L(
                    "credit_card.calendar_export.access_denied",
                    defaultValue: "Calendar access is unavailable. Allow it in iPhone Settings to add a payment."
                ))
            case .notDetermined:
                toastCenter.show(message: L(
                    "credit_card.calendar_export.unavailable",
                    defaultValue: "Calendar event could not be prepared"
                ))
            }
        }
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
