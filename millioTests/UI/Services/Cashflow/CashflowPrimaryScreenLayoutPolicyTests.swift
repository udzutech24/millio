//
//  CashflowPrimaryScreenLayoutPolicyTests.swift
//  millioTests
//


import CoreGraphics
import Testing
@testable import millio

struct CashflowPrimaryScreenLayoutPolicyTests {
    @Test("Primary action stays wider than month navigation on supported phone widths")
    func primaryActionRemainsDominant() {
        for width in [CGFloat(320), 351, 393, 430] {
            let secondary = CashflowPrimaryScreenLayoutPolicy.secondaryActionWidth(containerWidth: width)
            let primary = width - CashflowPrimaryScreenLayoutPolicy.actionSpacing - secondary

            #expect(primary > secondary)
        }
    }

    @Test("Secondary action width is clamped for narrow and wide layouts")
    func secondaryActionWidthIsClamped() {
        #expect(
            CashflowPrimaryScreenLayoutPolicy.secondaryActionWidth(containerWidth: 280)
                == CashflowPrimaryScreenLayoutPolicy.minimumSecondaryActionWidth
        )
        #expect(
            CashflowPrimaryScreenLayoutPolicy.secondaryActionWidth(containerWidth: 600)
                == CashflowPrimaryScreenLayoutPolicy.maximumSecondaryActionWidth
        )
    }

    @Test("Every asset row reserves a real trailing control slot")
    func assetColumnsHaveStableMetrics() {
        #expect(CashflowPrimaryScreenLayoutPolicy.assetValueColumnWidth >= 120)
        #expect(CashflowPrimaryScreenLayoutPolicy.assetControlSlotWidth >= 28)
    }
}
