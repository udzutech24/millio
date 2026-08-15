import Foundation

/// Canonical accounting policy for stock positions. FIFO is intentionally explicit so screens
/// cannot silently mix it with average-cost calculations.
enum StockLotAccountingPolicy: String, Codable, Sendable {
    case fifo
}

struct StockOpenLot: Equatable, Sendable {
    let sourceEventID: UUID
    var quantity: Decimal
    let unitCost: Decimal

    var costBasis: Decimal { quantity * unitCost }
}

struct StockPositionSnapshot: Equatable, Sendable {
    let policy: StockLotAccountingPolicy
    let quantity: Decimal
    let openLots: [StockOpenLot]
    let openCostBasis: Decimal
    let averageUnitCost: Decimal?
    let realizedProfitLoss: Decimal
    let dividends: Decimal
    let standaloneFees: Decimal
    let totalFees: Decimal

    func marketValue(at unitPrice: Decimal) -> Decimal { quantity * unitPrice }

    func unrealizedProfitLoss(at unitPrice: Decimal) -> Decimal {
        marketValue(at: unitPrice) - openCostBasis
    }

    func totalReturn(at unitPrice: Decimal) -> Decimal {
        realizedProfitLoss + unrealizedProfitLoss(at: unitPrice) + dividends - standaloneFees
    }
}

enum StockLotEngineError: Error, Equatable {
    case invalidQuantity
    case invalidUnitPrice
    case invalidFee
    case oversell(requested: Decimal, available: Decimal)
}

/// Pure, deterministic FIFO replay. For buy/sell events `amount` is the fee attached to that
/// trade. A standalone `.fee` event remains supported and is subtracted once from total return.
enum StockLotEngine {
    static func replay(events: [AccountEvent], on date: Date = .distantFuture) throws -> StockPositionSnapshot {
        let ordered = events
            .filter { $0.date <= date }
            .sorted(by: strictOrder)

        var lots: [StockOpenLot] = []
        var realized: Decimal = 0
        var dividends: Decimal = 0
        var standaloneFees: Decimal = 0
        var totalFees: Decimal = 0

        for event in ordered {
            switch event.type {
            case .buy:
                let quantity = try positive(event.quantity, error: .invalidQuantity)
                let price = try positive(event.unitPrice, error: .invalidUnitPrice)
                let fee = try nonNegative(event.amount)
                totalFees += fee
                lots.append(StockOpenLot(
                    sourceEventID: event.id,
                    quantity: quantity,
                    unitCost: price + fee / quantity
                ))

            case .sell:
                let quantity = try positive(event.quantity, error: .invalidQuantity)
                let price = try positive(event.unitPrice, error: .invalidUnitPrice)
                let fee = try nonNegative(event.amount)
                totalFees += fee
                let available = lots.reduce(Decimal.zero) { $0 + $1.quantity }
                guard quantity <= available else {
                    throw StockLotEngineError.oversell(requested: quantity, available: available)
                }
                let consumedCost = consumeFIFO(quantity: quantity, lots: &lots)
                realized += quantity * price - fee - consumedCost

            case .dividend:
                dividends += event.amount ?? 0

            case .fee:
                let fee = try nonNegative(event.amount)
                standaloneFees += fee
                totalFees += fee

            case .adjustment where event.quantity != nil:
                guard let quantity = event.quantity, quantity >= 0 else {
                    throw StockLotEngineError.invalidQuantity
                }
                if quantity == 0 {
                    lots.removeAll()
                } else {
                    let averageCost = try positive(event.unitPrice, error: .invalidUnitPrice)
                    lots = [StockOpenLot(
                        sourceEventID: event.id,
                        quantity: quantity,
                        unitCost: averageCost
                    )]
                }

            default:
                continue
            }
        }

        let quantity = lots.reduce(Decimal.zero) { $0 + $1.quantity }
        let costBasis = lots.reduce(Decimal.zero) { $0 + $1.costBasis }
        return StockPositionSnapshot(
            policy: .fifo,
            quantity: quantity,
            openLots: lots,
            openCostBasis: costBasis,
            averageUnitCost: quantity > 0 ? costBasis / quantity : nil,
            realizedProfitLoss: realized,
            dividends: dividends,
            standaloneFees: standaloneFees,
            totalFees: totalFees
        )
    }

    private static func consumeFIFO(quantity: Decimal, lots: inout [StockOpenLot]) -> Decimal {
        var remaining = quantity
        var cost: Decimal = 0
        while remaining > 0 {
            let consumed = min(remaining, lots[0].quantity)
            cost += consumed * lots[0].unitCost
            lots[0].quantity -= consumed
            remaining -= consumed
            if lots[0].quantity == 0 { lots.removeFirst() }
        }
        return cost
    }

    private static func positive(_ value: Decimal?, error: StockLotEngineError) throws -> Decimal {
        guard let value, value > 0 else { throw error }
        return value
    }

    private static func nonNegative(_ value: Decimal?) throws -> Decimal {
        let value = value ?? 0
        guard value >= 0 else { throw StockLotEngineError.invalidFee }
        return value
    }

    private static func strictOrder(_ lhs: AccountEvent, _ rhs: AccountEvent) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
