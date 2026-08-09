import Foundation

struct RealEstateValuationSummary: Equatable {
    let currentValue: Decimal?
    let previousValue: Decimal?
    let delta: Decimal?
    let percentDelta: Decimal?
    let lastValuationDate: Date?
    let ageInDays: Int?
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

    static func resolve(for account: Account) -> Self {
        if account.productType == .realEstate {
            return .init(kind: .realEstate, showsValuationHistory: true, supportsPhotos: true)
        }
        return .init(kind: .generic, showsValuationHistory: false, supportsPhotos: false)
    }
}
