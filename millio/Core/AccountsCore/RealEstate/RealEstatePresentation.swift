import Foundation

struct RealEstateValuationSummary: Equatable {
    let currentValue: Decimal?
    let previousValue: Decimal?
    let delta: Decimal?
    let percentDelta: Decimal?
    let lastValuationDate: Date?
    let ageInDays: Int?
}

/// Deterministic, locale-aware strings consumed by the real-estate summary UI.
/// Keeping formatting outside SwiftUI makes missing values and large amounts testable without
/// coupling the product contract to a particular screen composition.
struct RealEstateDetailPresentation: Equatable {
    let currentValue: String
    let currency: String
    let delta: String
    let percentDelta: String
    let lastValuationDate: String
    let ageInDays: String
    let equity: String?

    static func make(
        summary: RealEstateValuationSummary,
        currency: String,
        equity: Decimal?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> Self {
        let amountFormatter = decimalFormatter(locale: locale)
        let signedFormatter = decimalFormatter(locale: locale, usesPositivePrefix: true)

        return Self(
            currentValue: format(summary.currentValue, with: amountFormatter),
            currency: currency,
            delta: format(summary.delta, with: signedFormatter),
            percentDelta: summary.percentDelta.map { "\(format($0, with: signedFormatter))%" } ?? "—",
            lastValuationDate: format(summary.lastValuationDate, locale: locale, timeZone: timeZone),
            ageInDays: summary.ageInDays.map(String.init) ?? "—",
            equity: equity.map { format($0, with: amountFormatter) }
        )
    }

    private static func decimalFormatter(locale: Locale, usesPositivePrefix: Bool = false) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = true
        if usesPositivePrefix { formatter.positivePrefix = "+" }
        return formatter
    }

    private static func format(_ value: Decimal?, with formatter: NumberFormatter) -> String {
        guard let value else { return "—" }
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "—"
    }

    private static func format(_ date: Date?, locale: Locale, timeZone: TimeZone) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum RealEstateValuationCalculator {
    static func summary(
        events: [AccountEvent],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> RealEstateValuationSummary {
        let valuations = events
            .filter { ($0.type == .openingBalance || $0.type == .revaluation) && $0.date <= now }
            .sorted { lhs, rhs in
                lhs.date != rhs.date ? lhs.date < rhs.date : lhs.createdAt < rhs.createdAt
            }
        let current = valuations.last
        let previous = valuations.dropLast().last
        let currentValue = current?.amount
        let previousValue = previous?.amount
        let delta: Decimal?
        if let currentValue, let previousValue {
            delta = currentValue - previousValue
        } else {
            delta = nil
        }
        let percent: Decimal?
        if let delta, let previousValue, previousValue != 0 {
            percent = delta / previousValue * Decimal(100)
        } else {
            percent = nil
        }
        let age = current.map { max(0, calendar.dateComponents([.day], from: $0.date, to: now).day ?? 0) }
        return RealEstateValuationSummary(
            currentValue: currentValue,
            previousValue: previousValue,
            delta: delta,
            percentDelta: percent,
            lastValuationDate: current?.date,
            ageInDays: age
        )
    }
}

struct AccountDetailDescriptor: Equatable {
    enum Kind: Equatable { case generic, realEstate }
    let kind: Kind
    let showsValuationHistory: Bool
    let supportsPhotos: Bool

    /// Product-specific detail sections own their primary summary and must not be followed by the
    /// generic account header. This explicit contract prevents duplicated monetary information.
    var showsGenericHeader: Bool { kind == .generic }

    static func resolve(for account: Account) -> Self {
        if account.productType == .realEstate {
            return .init(kind: .realEstate, showsValuationHistory: true, supportsPhotos: true)
        }
        return .init(kind: .generic, showsValuationHistory: false, supportsPhotos: false)
    }
}
