//
//  WrappingLayoutCalculatorTests.swift
//  millioTests
//
//  Created by Codex on 08.03.2026.
//

import CoreGraphics
import Testing
@testable import millio

@Suite("Wrapping layout calculator")
struct WrappingLayoutCalculatorTests {
    @Test("Compute wraps items into multiple rows")
    func testComputeWrapsIntoRows() {
        let itemSizes = [
            CGSize(width: 80, height: 10),
            CGSize(width: 80, height: 10),
            CGSize(width: 80, height: 10)
        ]

        let result = WrappingLayoutCalculator.compute(
            itemSizes: itemSizes,
            maxWidth: 200,
            horizontalSpacing: 10,
            verticalSpacing: 12
        )

        #expect(result.rows.count == 2)
        #expect(result.rows[0].indices == [0, 1])
        #expect(result.rows[1].indices == [2])
        #expect(result.contentSize.width == 170)
        #expect(result.contentSize.height == CGFloat(10 + 12 + 10))
    }

    @Test("Compute caps items wider than max width")
    func testComputeCapsOversizedItems() {
        let itemSizes = [
            CGSize(width: 300, height: 10)
        ]

        let result = WrappingLayoutCalculator.compute(
            itemSizes: itemSizes,
            maxWidth: 200,
            horizontalSpacing: 10,
            verticalSpacing: 12
        )

        #expect(result.rows.count == 1)
        #expect(result.rows[0].width == 200)
        #expect(result.contentSize.width == 200)
    }

    @Test("Compute handles empty input")
    func testComputeEmptyInput() {
        let result = WrappingLayoutCalculator.compute(
            itemSizes: [],
            maxWidth: 200,
            horizontalSpacing: 10,
            verticalSpacing: 12
        )

        #expect(result.rows.isEmpty)
        #expect(result.contentSize == .zero)
    }
}
