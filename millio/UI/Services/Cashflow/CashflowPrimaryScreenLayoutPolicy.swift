//
//  CashflowPrimaryScreenLayoutPolicy.swift
//  millio
//
//  Stable metrics for the primary Cashflow action and asset-summary columns.
//

import CoreGraphics

enum CashflowPrimaryScreenLayoutPolicy {
    static let assetValueColumnWidth: CGFloat = 128
    static let assetControlSlotWidth: CGFloat = 28
    static let actionSpacing: CGFloat = 12
    static let secondaryActionFraction: CGFloat = 0.42
    static let minimumSecondaryActionWidth: CGFloat = 124
    static let maximumSecondaryActionWidth: CGFloat = 156

    static func secondaryActionWidth(containerWidth: CGFloat) -> CGFloat {
        let availableWidth = max(containerWidth - actionSpacing, 0)
        return min(
            max(availableWidth * secondaryActionFraction, minimumSecondaryActionWidth),
            maximumSecondaryActionWidth
        )
    }
}
