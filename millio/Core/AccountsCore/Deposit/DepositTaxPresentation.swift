import Foundation

enum DepositTaxIncompleteReason: String, Equatable, Hashable, Sendable {
    case missingHistoricalFX = "missing_historical_fx"
    case invalidHistoricalFX = "invalid_historical_fx"
    case missingTaxSettings = "missing_tax_settings"
}

struct DepositHistoricalFXKey: Hashable, Sendable {
    let dayKey: String
    let base: String
    let quote: String
}

struct DepositTaxEvent: Sendable {
    let accountID: UUID
    let date: Date
    let currency: String
    let amount: Decimal
}

struct DepositTaxPresentation: Equatable, Sendable {
    let year: Int
    let result: DepositTaxResult?
    let unresolved: [DepositTaxIncompleteReason]
    var isComplete: Bool { result != nil && unresolved.isEmpty }
}

/// Owner-wide tax adapter. It accepts only event-date evidence and never falls back to a current
/// quote or relabels a foreign nominal amount as RUB.
enum DepositTaxPresentationBuilder {
    static func make(
        events: [DepositTaxEvent],
        year: Int,
        settings: DepositTaxSettings?,
        historicalFX: [DepositHistoricalFXKey: Decimal],
        calendar: Calendar
    ) -> DepositTaxPresentation {
        guard let settings else {
            return .init(year: year, result: nil, unresolved: [.missingTaxSettings])
        }
        var unresolved = Set<DepositTaxIncompleteReason>()
        let inputs = events.compactMap { event -> DepositTaxCalculator.InterestEventInput? in
            guard calendar.component(.year, from: event.date) == year else { return nil }
            let currency = event.currency.uppercased()
            if currency == "RUB" { return .init(accountID: event.accountID, amountRUB: event.amount) }
            let day = dayKey(event.date, calendar: calendar)
            if let direct = historicalFX[.init(dayKey: day, base: currency, quote: "RUB")] {
                guard direct > 0, !direct.isNaN else { unresolved.insert(.invalidHistoricalFX); return nil }
                return .init(accountID: event.accountID, amountRUB: event.amount * direct)
            }
            if let inverse = historicalFX[.init(dayKey: day, base: "RUB", quote: currency)] {
                guard inverse > 0, !inverse.isNaN else { unresolved.insert(.invalidHistoricalFX); return nil }
                return .init(accountID: event.accountID, amountRUB: event.amount / inverse)
            }
            unresolved.insert(.missingHistoricalFX)
            return nil
        }
        guard unresolved.isEmpty else {
            return .init(year: year, result: nil, unresolved: unresolved.sorted { $0.rawValue < $1.rawValue })
        }
        return .init(
            year: year,
            result: DepositTaxCalculator.calculate(interestEventsInRUB: inputs, year: year, settings: settings),
            unresolved: []
        )
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
