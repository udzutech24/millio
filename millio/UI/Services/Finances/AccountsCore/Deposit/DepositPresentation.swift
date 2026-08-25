import Foundation

enum DepositDetailState: Equatable {
    case normal
    case savings
    case dueSoon
    case maturedNeedsAction
    case archived
    case incomplete
}

enum DepositDetailAction: Hashable {
    case topUp
    case adjustBalance
    case editTerms
    case earlyClose
    case withdrawAtMaturity
    case archive
}

struct DepositEarlyClosePreview: Equatable {
    let lostInterest: Decimal
    let penalty: Decimal
    let netProceeds: Decimal
}

struct DepositCreationPreview: Equatable {
    enum ValidationError: Equatable {
        case invalidAmount
        case invalidRate
        case invalidTerm
        case invalidPenalty
        case termRequiredForLifecycleOption
    }

    let interest: Decimal?
    let maturityAmount: Decimal?
    let errors: [ValidationError]

    var isValid: Bool { errors.isEmpty }

    static func make(
        amount: Decimal?,
        rate: Decimal?,
        openingDate: Date,
        termEnd: Date?,
        hasTerm: Bool,
        earlyClosePenaltyPercent: Decimal?,
        allowsEarlyClose: Bool,
        remindEnd: Bool,
        autoRollover: Bool,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> Self {
        var errors: [ValidationError] = []
        if amount.map({ $0 > 0 && !$0.isNaN }) != true { errors.append(.invalidAmount) }
        if rate.map({ $0 > 0 && !$0.isNaN }) != true { errors.append(.invalidRate) }
        if hasTerm && termEnd.map({ $0 > openingDate }) != true { errors.append(.invalidTerm) }
        if allowsEarlyClose,
           earlyClosePenaltyPercent.map({ $0 >= 0 && $0 <= 100 && !$0.isNaN }) != true {
            errors.append(.invalidPenalty)
        }
        if !hasTerm && (remindEnd || autoRollover) { errors.append(.termRequiredForLifecycleOption) }

        guard errors.isEmpty, let amount, let rate else {
            return .init(interest: nil, maturityAmount: nil, errors: errors)
        }
        guard hasTerm, let termEnd else {
            return .init(interest: nil, maturityAmount: nil, errors: [])
        }
        let days = max(0, calendar.dateComponents([.day], from: openingDate, to: termEnd).day ?? 0)
        let interest = DepositInterestScheduler.round2(amount * rate / 100 * Decimal(days) / 365)
        return .init(interest: interest, maturityAmount: amount + interest, errors: [])
    }
}

struct DepositDetailPresentation: Equatable {
    let state: DepositDetailState
    let actions: [DepositDetailAction]
    let snapshot: DepositPresentationSnapshot

    static func make(snapshot: DepositPresentationSnapshot) -> Self {
        let state: DepositDetailState = switch snapshot.lifecycleState {
        case .active: .normal
        case .openEnded: .savings
        case .dueSoon: .dueSoon
        case .maturedNeedsAction: .maturedNeedsAction
        case .closed: .archived
        case .incomplete: .incomplete
        }

        let actions: [DepositDetailAction]
        switch state {
        case .archived, .incomplete:
            actions = []
        case .maturedNeedsAction:
            actions = [.withdrawAtMaturity]
        case .normal, .savings, .dueSoon:
            var available: [DepositDetailAction] = []
            if snapshot.capabilities.allowsTopUp { available.append(.topUp) }
            available.append(.adjustBalance)
            available.append(.editTerms)
            if snapshot.capabilities.allowsEarlyClose { available.append(.earlyClose) }
            available.append(.archive)
            actions = available
        }
        return .init(state: state, actions: actions, snapshot: snapshot)
    }

    static func earlyClosePreview(snapshot: DepositPresentationSnapshot, penaltyShare: Decimal?) -> DepositEarlyClosePreview? {
        guard let balance = snapshot.currentBalance.value,
              let confirmedInterest = snapshot.confirmedInterest.value else { return nil }
        let lostInterest = max(0, snapshot.estimatedDueInterest.value ?? 0) + max(0, snapshot.futureInterest.value ?? 0)
        let penalty = DepositInterestScheduler.round2(max(0, confirmedInterest) * max(0, penaltyShare ?? 0))
        return .init(lostInterest: lostInterest, penalty: penalty, netProceeds: max(0, balance - penalty))
    }

    static func isGeneratedForecastEvent(_ event: AccountEvent, accountID: UUID) -> Bool {
        event.type == .interest
            && event.sourceTransactionID?.hasPrefix("deposit-interest:\(accountID.uuidString):") == true
    }
}
