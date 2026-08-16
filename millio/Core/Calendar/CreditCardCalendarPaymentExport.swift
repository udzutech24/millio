import Foundation

/// Builds the one-way Calendar draft from the same payment policy that drives the credit-card UI.
/// This boundary intentionally cannot infer a payment amount from the outstanding debt or limit.
struct CreditCardCalendarPaymentExport {
    private let calendar: Calendar
    private let now: () -> Date
    private let locale: Locale

    init(calendar: Calendar = .current, now: @escaping () -> Date = Date.init, locale: Locale = .current) {
        self.calendar = calendar
        self.now = now
        self.locale = locale
    }

    func makePayload(
        cardName: String,
        paymentStatus: CreditCardPaymentStatus,
        settings: CreditCardPaymentSettings,
        minimumPayment: Decimal?,
        currency: String
    ) -> AppleCalendarEventExportPayload? {
        guard AppleCalendarEventExportEligibility.isEligible(
            scheduledDate: paymentStatus.dueDate,
            now: now(),
            calendar: calendar
        ) else {
            return nil
        }

        let notes = minimumPayment.map { formattedMinimumPayment($0, currency: currency) }
        return AppleCalendarEventExportPayloadBuilder(calendar: calendar).makePayload(
            title: cardName,
            notes: notes,
            scheduledDate: paymentStatus.dueDate,
            hour: settings.reminderHour,
            minute: settings.reminderMinute
        )
    }

    private func formattedMinimumPayment(_ amount: Decimal, currency: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 2
        let formatted = formatter.string(from: amount as NSNumber) ?? NSDecimalNumber(decimal: amount).stringValue
        return "\(formatted) \(currency)"
    }
}
