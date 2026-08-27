import Foundation

enum DepositValueProvenance: Equatable, Sendable {
    case confirmed
    case estimated
    case unavailable
}

struct DepositAmount: Equatable, Sendable {
    let value: Decimal?
    let provenance: DepositValueProvenance

    static func confirmed(_ value: Decimal) -> Self {
        .init(value: value, provenance: .confirmed)
    }

    static func estimated(_ value: Decimal) -> Self {
        .init(value: value, provenance: .estimated)
    }

    static let unavailable = Self(value: nil, provenance: .unavailable)
}

struct DepositAccrual: Equatable, Sendable {
    let date: Date
    let amount: DepositAmount
}

enum DepositLifecycleState: Equatable, Sendable {
    case active
    case dueSoon
    case openEnded
    case maturedNeedsAction
    case closed
    case incomplete
}

enum DepositUnresolvedReason: String, Equatable, Hashable, Sendable {
    case missingMetadata = "missing_metadata"
    case invalidRate = "invalid_rate"
    case invalidTerm = "invalid_term"
    case invalidCurrency = "invalid_currency"
    case invalidEventAmount = "invalid_event_amount"
    case missingGeneratedSchedule = "missing_generated_schedule"
    case unsupportedDayCountConvention = "unsupported_day_count_convention"
    case unsupportedVariableRate = "unsupported_variable_rate"
    case unsupportedWithdrawalPolicy = "unsupported_withdrawal_policy"
}

struct DepositCapabilities: Equatable, Sendable {
    let allowsTopUp: Bool
    let allowsEarlyClose: Bool
    /// Existing metadata has no partial-withdrawal contract. Returning false is safer than
    /// presenting the generic transfer capability as a supported deposit operation.
    let allowsWithdrawal: Bool
    let reminderIsOperational: Bool
    let autoRolloverIsOperational: Bool
}

struct DepositPresentationSnapshot: Equatable, Sendable {
    let asOf: Date
    let currency: String
    let principal: DepositAmount
    let confirmedInterest: DepositAmount
    let estimatedDueInterest: DepositAmount
    let futureInterest: DepositAmount
    let currentBalance: DepositAmount
    let projectedBalance: DepositAmount
    let availableToWithdraw: DepositAmount
    let nextAccrual: DepositAccrual?
    let maturityDate: Date?
    let maturityAmount: DepositAmount
    let daysRemaining: Int?
    let progress: Decimal?
    let lifecycleState: DepositLifecycleState
    let capabilities: DepositCapabilities
    let unresolved: [DepositUnresolvedReason]
}

enum DepositFinancialContract {
    enum RatePolicy: Equatable, Sendable {
        case fixed
        case variableUnsupported
    }

    static func snapshot(
        accountID: UUID,
        currency: String,
        openingDate: Date,
        archivedAt: Date? = nil,
        deletedAt: Date? = nil,
        meta: DepositMeta?,
        events: [AccountEvent],
        asOf: Date,
        calendarPolicy: DepositCalendarPolicy,
        ratePolicy: RatePolicy = .fixed
    ) -> DepositPresentationSnapshot {
        var unresolved = Set<DepositUnresolvedReason>()
        if currency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            unresolved.insert(.invalidCurrency)
        }
        if ratePolicy == .variableUnsupported {
            unresolved.insert(.unsupportedVariableRate)
        }
        if calendarPolicy.dayCountConvention != .act365 {
            unresolved.insert(.unsupportedDayCountConvention)
        }
        guard let meta else {
            unresolved.insert(.missingMetadata)
            return incompleteSnapshot(
                currency: currency, asOf: asOf, archivedAt: archivedAt, deletedAt: deletedAt,
                unresolved: unresolved
            )
        }
        if meta.rate <= 0 { unresolved.insert(.invalidRate) }
        if let termEnd = meta.termEnd, termEnd <= openingDate { unresolved.insert(.invalidTerm) }
        if events.contains(where: { event in
            guard let amount = event.amount else { return false }
            return amount.isNaN || (event.type == .interest && amount < 0)
        }) {
            unresolved.insert(.invalidEventAmount)
        }

        let orderedEvents = events.sorted(by: stableOrder)
        let confirmedInterestDays = Set(orderedEvents.compactMap { event -> String? in
            guard event.type == .interest,
                  event.date <= asOf,
                  !isGeneratedInterest(event, accountID: accountID),
                  (event.amount ?? 0) >= 0 else { return nil }
            return calendarPolicy.dayKey(for: event.date)
        })
        let eligibleGenerated = orderedEvents.filter { event in
            isGeneratedInterest(event, accountID: accountID)
                && !confirmedInterestDays.contains(calendarPolicy.dayKey(for: event.date))
        }
        if eligibleGenerated.isEmpty,
           meta.termEnd.map({ $0 > asOf }) ?? true,
           !unresolved.contains(.invalidRate),
           !unresolved.contains(.invalidTerm) {
            unresolved.insert(.missingGeneratedSchedule)
        }
        let actualEvents = orderedEvents.filter { event in
            !isGeneratedInterest(event, accountID: accountID) && event.date <= asOf
        }

        let fatalFinancialState = unresolved.contains(.invalidCurrency)
            || unresolved.contains(.invalidRate)
            || unresolved.contains(.invalidTerm)
            || unresolved.contains(.invalidEventAmount)
            || unresolved.contains(.unsupportedDayCountConvention)
            || unresolved.contains(.unsupportedVariableRate)

        let principalValue = actualEvents.reduce(Decimal.zero) { result, event in
            result + principalContribution(event)
        }
        let confirmedInterestValue = actualEvents.reduce(Decimal.zero) { result, event in
            result + (event.type == .interest ? (event.amount ?? 0) : 0)
        }
        let estimatedDueValue = eligibleGenerated.reduce(Decimal.zero) { result, event in
            result + (event.date <= asOf ? (event.amount ?? 0) : 0)
        }
        let futureInterestValue = eligibleGenerated.reduce(Decimal.zero) { result, event in
            result + (event.date > asOf ? (event.amount ?? 0) : 0)
        }
        // Ровно та же формула, что у списка/тоталов/снапшотов (Ф1 плана
        // `2026-08-26__deposit-confirmed-balance-unification.md`) — один резолвер, одна цифра.
        let currentBalanceValue = DepositConfirmedBalanceResolver.balanceAt(
            events: orderedEvents, accountID: accountID, on: asOf
        )

        let projectionDate = meta.termEnd ?? eligibleGenerated.map(\.date).max() ?? asOf
        let projectionEvents = actualEvents + eligibleGenerated.filter { $0.date <= projectionDate }
        let projectedBalanceValue = AccountBalanceEngine.balanceAt(
            events: projectionEvents, kind: .deposit, on: projectionDate
        )

        let nextAccrual = eligibleGenerated
            .filter { $0.date > asOf && ($0.amount ?? 0) >= 0 }
            .min(by: stableOrder)
            .flatMap { event in
                event.amount.map { DepositAccrual(date: event.date, amount: .estimated($0)) }
            }

        let lifecycle = lifecycleState(
            openingDate: openingDate, maturity: meta.termEnd, archivedAt: archivedAt,
            deletedAt: deletedAt, asOf: asOf, calendarPolicy: calendarPolicy,
            isIncomplete: fatalFinancialState
        )
        let daysRemaining = meta.termEnd.map { calendarPolicy.daysRemaining(from: asOf, to: $0) }
        let progress = meta.termEnd.flatMap { maturity -> Decimal? in
            guard maturity > openingDate else { return nil }
            if asOf <= openingDate { return 0 }
            if asOf >= maturity { return 1 }
            let total = maturity.timeIntervalSince(openingDate)
            return Decimal(asOf.timeIntervalSince(openingDate) / total)
        }
        let projectionIsFullyConfirmed = meta.termEnd.map { $0 <= asOf } == true
            && eligibleGenerated.isEmpty
        let hasProjection = !eligibleGenerated.isEmpty || projectionIsFullyConfirmed
        let projectedAmount: DepositAmount = if fatalFinancialState || !hasProjection {
            .unavailable
        } else if projectionIsFullyConfirmed {
            .confirmed(projectedBalanceValue)
        } else {
            .estimated(projectedBalanceValue)
        }

        // Early-close support still does not define partial withdrawal availability.
        unresolved.insert(.unsupportedWithdrawalPolicy)

        let acceptsActiveOperations = lifecycle == .active
            || lifecycle == .dueSoon
            || lifecycle == .openEnded

        return DepositPresentationSnapshot(
            asOf: asOf,
            currency: currency,
            principal: fatalFinancialState ? .unavailable : .confirmed(principalValue),
            confirmedInterest: fatalFinancialState ? .unavailable : .confirmed(confirmedInterestValue),
            estimatedDueInterest: fatalFinancialState || eligibleGenerated.isEmpty ? .unavailable : .estimated(estimatedDueValue),
            futureInterest: fatalFinancialState || eligibleGenerated.isEmpty ? .unavailable : .estimated(futureInterestValue),
            currentBalance: fatalFinancialState ? .unavailable : .confirmed(currentBalanceValue),
            projectedBalance: projectedAmount,
            availableToWithdraw: .unavailable,
            nextAccrual: fatalFinancialState ? nil : nextAccrual,
            maturityDate: meta.termEnd,
            maturityAmount: meta.termEnd == nil ? .unavailable : projectedAmount,
            daysRemaining: daysRemaining,
            progress: progress,
            lifecycleState: lifecycle,
            capabilities: DepositCapabilities(
                allowsTopUp: meta.allowsTopUp && acceptsActiveOperations,
                allowsEarlyClose: meta.allowsEarlyClose && acceptsActiveOperations,
                allowsWithdrawal: false,
                reminderIsOperational: false,
                autoRolloverIsOperational: false
            ),
            unresolved: unresolved.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func incompleteSnapshot(
        currency: String,
        asOf: Date,
        archivedAt: Date?,
        deletedAt: Date?,
        unresolved: Set<DepositUnresolvedReason>
    ) -> DepositPresentationSnapshot {
        let closed = [archivedAt, deletedAt].compactMap { $0 }.contains { $0 <= asOf }
        return DepositPresentationSnapshot(
            asOf: asOf, currency: currency,
            principal: .unavailable, confirmedInterest: .unavailable,
            estimatedDueInterest: .unavailable, futureInterest: .unavailable,
            currentBalance: .unavailable, projectedBalance: .unavailable,
            availableToWithdraw: .unavailable, nextAccrual: nil, maturityDate: nil,
            maturityAmount: .unavailable, daysRemaining: nil, progress: nil,
            lifecycleState: closed ? .closed : .incomplete,
            capabilities: .init(
                allowsTopUp: false, allowsEarlyClose: false, allowsWithdrawal: false,
                reminderIsOperational: false, autoRolloverIsOperational: false
            ),
            unresolved: unresolved.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func isGeneratedInterest(_ event: AccountEvent, accountID: UUID) -> Bool {
        DepositConfirmedBalanceResolver.isGeneratedInterest(event, accountID: accountID)
    }

    private static func principalContribution(_ event: AccountEvent) -> Decimal {
        let amount = event.amount ?? 0
        switch event.type {
        case .openingBalance, .income, .transferIn, .adjustment:
            return amount
        case .expense, .transferOut:
            return -amount
        default:
            return 0
        }
    }

    private static func stableOrder(_ lhs: AccountEvent, _ rhs: AccountEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func lifecycleState(
        openingDate: Date,
        maturity: Date?,
        archivedAt: Date?,
        deletedAt: Date?,
        asOf: Date,
        calendarPolicy: DepositCalendarPolicy,
        isIncomplete: Bool
    ) -> DepositLifecycleState {
        if [archivedAt, deletedAt].compactMap({ $0 }).contains(where: { $0 <= asOf }) { return .closed }
        if isIncomplete { return .incomplete }
        guard let maturity else { return .openEnded }
        if maturity <= openingDate { return .incomplete }
        if maturity <= asOf { return .maturedNeedsAction }
        return calendarPolicy.daysRemaining(from: asOf, to: maturity) <= 30 ? .dueSoon : .active
    }
}
