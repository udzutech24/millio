import Foundation
import Testing
@testable import millio

@Suite("Stock FIFO lot engine")
struct StockLotEngineTests {
    private let day1 = Date(timeIntervalSince1970: 1_700_000_000)
    private let day2 = Date(timeIntervalSince1970: 1_700_086_400)
    private let day3 = Date(timeIntervalSince1970: 1_700_172_800)

    private func event(
        id: UUID = UUID(), date: Date, createdAt: Date? = nil, type: AccountEventType,
        amount: Decimal? = nil, quantity: Decimal? = nil, unitPrice: Decimal? = nil
    ) -> AccountEvent {
        AccountEvent(
            id: id, date: date, createdAt: createdAt ?? date, type: type,
            amount: amount, quantity: quantity, unitPrice: unitPrice
        )
    }

    @Test("Sequential buys preserve FIFO lots and weighted average cost")
    func sequentialBuys() throws {
        let snapshot = try StockLotEngine.replay(events: [
            event(date: day1, type: .buy, amount: 10, quantity: 10, unitPrice: 100),
            event(date: day2, type: .buy, amount: 5, quantity: 5, unitPrice: 120)
        ])

        #expect(snapshot.quantity == 15)
        #expect(snapshot.openCostBasis == 1_615)
        #expect(snapshot.averageUnitCost == Decimal(1_615) / 15)
        #expect(snapshot.openLots.map(\.unitCost) == [101, 121])
        #expect(snapshot.totalFees == 15)
    }

    @Test("Partial sale consumes FIFO cost and subtracts sell fee once")
    func partialSale() throws {
        let snapshot = try StockLotEngine.replay(events: [
            event(date: day1, type: .buy, amount: 10, quantity: 10, unitPrice: 100),
            event(date: day2, type: .buy, quantity: 5, unitPrice: 120),
            event(date: day3, type: .sell, amount: 7, quantity: 12, unitPrice: 150)
        ])

        #expect(snapshot.quantity == 3)
        #expect(snapshot.openCostBasis == 360)
        #expect(snapshot.realizedProfitLoss == Decimal(1_800 - 7 - 1_250))
        #expect(snapshot.unrealizedProfitLoss(at: 140) == 60)
    }

    @Test("Full close retains realized return and has no false percentage denominator")
    func fullClose() throws {
        let snapshot = try StockLotEngine.replay(events: [
            event(date: day1, type: .buy, quantity: 0.5, unitPrice: 10.12345678),
            event(date: day2, type: .sell, quantity: 0.5, unitPrice: 12.12345678),
            event(date: day3, type: .dividend, amount: 0.25)
        ])

        #expect(snapshot.quantity == 0)
        #expect(snapshot.openCostBasis == 0)
        #expect(snapshot.averageUnitCost == nil)
        #expect(snapshot.realizedProfitLoss == 1)
        #expect(snapshot.totalReturn(at: 999) == 1.25)
    }

    @Test("Oversell fails instead of creating a short position")
    func oversell() {
        #expect(throws: StockLotEngineError.oversell(requested: 2, available: 1)) {
            try StockLotEngine.replay(events: [
                event(date: day1, type: .buy, quantity: 1, unitPrice: 100),
                event(date: day2, type: .sell, quantity: 2, unitPrice: 110)
            ])
        }
    }

    @Test("Replay is deterministic for unsorted fetch results")
    func deterministicReplay() throws {
        let buy1 = event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, date: day1, type: .buy, quantity: 2, unitPrice: 10)
        let buy2 = event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, date: day2, type: .buy, quantity: 2, unitPrice: 20)
        let sell = event(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, date: day3, type: .sell, quantity: 3, unitPrice: 30)

        let expected = try StockLotEngine.replay(events: [buy1, buy2, sell])
        #expect(try StockLotEngine.replay(events: [sell, buy1, buy2]) == expected)
        #expect(try StockLotEngine.replay(events: [buy2, sell, buy1]) == expected)
    }

    @Test("Invalid zero and negative inputs are rejected")
    func invalidInputs() {
        #expect(throws: StockLotEngineError.invalidQuantity) {
            try StockLotEngine.replay(events: [event(date: day1, type: .buy, quantity: 0, unitPrice: 1)])
        }
        #expect(throws: StockLotEngineError.invalidUnitPrice) {
            try StockLotEngine.replay(events: [event(date: day1, type: .buy, quantity: 1, unitPrice: -1)])
        }
        #expect(throws: StockLotEngineError.invalidFee) {
            try StockLotEngine.replay(events: [event(date: day1, type: .buy, amount: -1, quantity: 1, unitPrice: 1)])
        }
    }

    @Test("Absolute correction replaces open lots without creating realized P&L")
    func absoluteCorrection() throws {
        let snapshot = try StockLotEngine.replay(events: [
            event(date: day1, type: .buy, quantity: 10, unitPrice: 100),
            event(date: day2, type: .adjustment, quantity: 7.5, unitPrice: 123.4567)
        ])

        #expect(snapshot.quantity == 7.5)
        #expect(snapshot.averageUnitCost == 123.4567)
        #expect(snapshot.openCostBasis == Decimal(string: "925.92525"))
        #expect(snapshot.realizedProfitLoss == 0)
    }
}
