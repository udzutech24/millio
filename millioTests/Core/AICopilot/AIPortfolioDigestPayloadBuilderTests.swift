import Foundation
import XCTest
@testable import millio

/// Цифры дайджеста: доли делятся на знаменатель экрана позиции, изменение — ценовое, от начала окна.
final class AIPortfolioDigestPayloadBuilderTests: XCTestCase {
    private func input(
        _ symbol: String,
        quantity: Decimal,
        value: Decimal,
        start: Decimal?,
        average: Decimal? = nil
    ) -> AIPortfolioDigestPayloadBuilder.PositionInput {
        AIPortfolioDigestPayloadBuilder.PositionInput(
            accountID: UUID(),
            name: symbol,
            symbol: symbol,
            assetClass: .stock,
            quantity: quantity,
            value: value,
            startUnitPrice: start,
            averageUnitCost: average
        )
    }

    private func rounded(_ value: Decimal) -> Double {
        AIPortfolioDigestPayloadBuilder.rounded(value)
    }

    func testSharesUsePortfolioTotalAndPositionsAreSortedByValue() throws {
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .month,
            currency: "RUB",
            positions: [
                input("SBER", quantity: 10, value: 3_000, start: 280),
                input("YNDX", quantity: 2, value: 8_000, start: 4_000),
                input("GAZP", quantity: 20, value: 3_000, start: 120)
            ],
            portfolioTotal: 14_000
        ))

        XCTAssertEqual(figures.positions.map(\.symbol), ["YNDX", "GAZP", "SBER"])
        XCTAssertEqual(figures.value, 14_000)
        XCTAssertEqual(figures.positions[0].sharePercent, Decimal(8_000) / 14_000 * 100)
    }

    /// SBER 280 → 300 (+7,14%), GAZP 120 → 150 (+25%): вклад 200 + 600 на базе 2800 + 2400.
    func testChangeIsPriceMovementOfCurrentHoldings() throws {
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .month,
            currency: "RUB",
            positions: [
                input("SBER", quantity: 10, value: 3_000, start: 280),
                input("GAZP", quantity: 20, value: 3_000, start: 120)
            ],
            portfolioTotal: 6_000
        ))

        XCTAssertEqual(figures.changeAmount, 800)
        XCTAssertEqual(rounded(figures.changePercent), 15.38)
        XCTAssertEqual(rounded(try XCTUnwrap(figures.positions.first { $0.symbol == "SBER" }).changePercent), 7.14)
        XCTAssertEqual(rounded(try XCTUnwrap(figures.positions.first { $0.symbol == "GAZP" }).changePercent), 25)
    }

    func testPositionOpenedInsideWindowIsMeasuredFromAverageCost() throws {
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .quarter,
            currency: "RUB",
            positions: [input("NEW", quantity: 4, value: 440, start: nil, average: 100)],
            portfolioTotal: 440
        ))

        XCTAssertEqual(figures.changeAmount, 40)
        XCTAssertEqual(rounded(figures.positions[0].changePercent), 10)
    }

    func testPositionWithoutAnyReferencePriceStaysOutOfTheChangeBase() throws {
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .month,
            currency: "RUB",
            positions: [
                input("SBER", quantity: 10, value: 3_000, start: 280),
                input("UNKNOWN", quantity: 1, value: 1_000, start: nil, average: nil)
            ],
            portfolioTotal: 4_000
        ))

        XCTAssertEqual(figures.changeAmount, 200)
        XCTAssertEqual(rounded(figures.changePercent), 7.14)
        XCTAssertEqual(try XCTUnwrap(figures.positions.first { $0.symbol == "UNKNOWN" }).changePercent, 0)
    }

    func testClosedPositionsAreDroppedAndEmptyPortfolioGivesNoFigures() {
        XCTAssertNil(AIPortfolioDigestPayloadBuilder.figures(
            window: .month,
            currency: "RUB",
            positions: [input("SOLD", quantity: 0, value: 0, start: 10)],
            portfolioTotal: 0
        ))
        XCTAssertNil(AIPortfolioDigestPayloadBuilder.figures(
            window: .month,
            currency: "RUB",
            positions: [],
            portfolioTotal: 1_000
        ))
    }

    func testRequestRoundsToHundredthsAndMapsLocale() throws {
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .quarter,
            currency: "RUB",
            positions: [input("SBER", quantity: 3, value: Decimal(string: "1234.5678")!, start: 400)],
            portfolioTotal: Decimal(string: "1234.5678")!
        ))

        let request = AIPortfolioDigestPayloadBuilder.makeRequest(figures: figures, locale: Locale(identifier: "zh_Hans_CN"))

        XCTAssertEqual(request.schemaVersion, "1")
        XCTAssertEqual(request.locale, "zh-Hans")
        XCTAssertEqual(request.window, "quarter")
        XCTAssertEqual(request.totals.value, 1_234.57)
        XCTAssertEqual(request.positions.first?.value, 1_234.57)
        XCTAssertEqual(request.positions.first?.sharePercent, 100)
        XCTAssertEqual(request.positions.first?.assetClass, "stock")
        XCTAssertEqual(AIPortfolioDigestPayloadBuilder.makeRequest(figures: figures, locale: Locale(identifier: "de_DE")).locale, "en")
    }

    /// Пределы DTO: 64 позиции, тикер ≤ 32, валюта ≤ 8 — иначе строгий бэкенд вернёт 400.
    func testRequestKeepsDtoLimitsAndDropsTheSmallestPositions() throws {
        let longTail = "X" + String(repeating: "Y", count: 40)
        let positions = (1...70).map { index in
            input("\(longTail)\(index)", quantity: 1, value: Decimal(index), start: Decimal(index))
        }
        let total = positions.reduce(Decimal.zero) { $0 + $1.value }
        let figures = try XCTUnwrap(AIPortfolioDigestPayloadBuilder.figures(
            window: .year,
            currency: "VERYLONGCODE",
            positions: positions,
            portfolioTotal: total
        ))

        let request = AIPortfolioDigestPayloadBuilder.makeRequest(figures: figures, locale: Locale(identifier: "ru_RU"))

        XCTAssertEqual(request.positions.count, 64)
        XCTAssertTrue(request.positions.allSatisfy { $0.symbol.count <= 32 })
        XCTAssertEqual(request.currency.count, 8)
        XCTAssertEqual(request.positions.last?.value, 7)
        XCTAssertEqual(request.totals.value, NSDecimalNumber(decimal: total).doubleValue)
    }
}
