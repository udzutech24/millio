//
//  WrappingHStack.swift
//  millio
//
//  Created by Codex on 08.03.2026.
//

import SwiftUI

enum WrappingRowAlignment {
    case leading
    case center
    case trailing
}

struct WrappingLayoutRow: Equatable {
    var indices: [Int]
    var width: CGFloat
    var height: CGFloat
}

struct WrappingLayoutResult: Equatable {
    var rows: [WrappingLayoutRow]
    var contentSize: CGSize
}

struct WrappingLayoutCalculator {
    static func compute(
        itemSizes: [CGSize],
        maxWidth: CGFloat,
        horizontalSpacing: CGFloat,
        verticalSpacing: CGFloat
    ) -> WrappingLayoutResult {
        guard !itemSizes.isEmpty else {
            return WrappingLayoutResult(rows: [], contentSize: .zero)
        }

        let effectiveMaxWidth = max(0, maxWidth)

        var rows: [WrappingLayoutRow] = []
        rows.reserveCapacity(max(1, itemSizes.count / 2))

        var currentIndices: [Int] = []
        currentIndices.reserveCapacity(4)

        var currentRowWidth: CGFloat = 0
        var currentRowHeight: CGFloat = 0

        func finalizeRowIfNeeded() {
            guard !currentIndices.isEmpty else { return }
            rows.append(
                WrappingLayoutRow(
                    indices: currentIndices,
                    width: currentRowWidth,
                    height: currentRowHeight
                )
            )
            currentIndices = []
            currentIndices.reserveCapacity(4)
            currentRowWidth = 0
            currentRowHeight = 0
        }

        for (index, size) in itemSizes.enumerated() {
            let itemWidth = min(size.width, effectiveMaxWidth)
            let itemHeight = size.height

            if currentIndices.isEmpty {
                currentIndices.append(index)
                currentRowWidth = itemWidth
                currentRowHeight = itemHeight
                continue
            }

            let proposedRowWidth = currentRowWidth + horizontalSpacing + itemWidth
            if proposedRowWidth <= effectiveMaxWidth {
                currentIndices.append(index)
                currentRowWidth = proposedRowWidth
                currentRowHeight = max(currentRowHeight, itemHeight)
            } else {
                finalizeRowIfNeeded()
                currentIndices.append(index)
                currentRowWidth = itemWidth
                currentRowHeight = itemHeight
            }
        }

        finalizeRowIfNeeded()

        let contentWidth = rows.map(\.width).max() ?? 0
        let contentHeight: CGFloat = rows.enumerated().reduce(0) { partial, pair in
            let (rowIndex, row) = pair
            if rowIndex == 0 { return row.height }
            return partial + verticalSpacing + row.height
        }

        return WrappingLayoutResult(
            rows: rows,
            contentSize: CGSize(width: contentWidth, height: contentHeight)
        )
    }
}

struct WrappingHStack: Layout {
    var alignment: WrappingRowAlignment = .leading
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    struct Cache {
        var maxWidth: CGFloat = 0
        var itemSizes: [CGSize] = []
        var result: WrappingLayoutResult = WrappingLayoutResult(rows: [], contentSize: .zero)
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(itemSizes: Array(repeating: .zero, count: subviews.count))
    }

    func updateCache(_ cache: inout Cache, proposal: ProposedViewSize, subviews: Subviews) {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        if cache.maxWidth == maxWidth, cache.itemSizes.count == subviews.count { return }

        cache.maxWidth = maxWidth
        if cache.itemSizes.count != subviews.count {
            cache.itemSizes = Array(repeating: .zero, count: subviews.count)
        }

        for index in subviews.indices {
            let measured = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: proposal.height))
            cache.itemSizes[index] = measured
        }

        cache.result = WrappingLayoutCalculator.compute(
            itemSizes: cache.itemSizes,
            maxWidth: maxWidth,
            horizontalSpacing: horizontalSpacing,
            verticalSpacing: verticalSpacing
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        updateCache(&cache, proposal: proposal, subviews: subviews)
        let width = proposal.width ?? cache.result.contentSize.width
        return CGSize(width: width, height: cache.result.contentSize.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let maxWidth = bounds.width
        let proposal = ProposedViewSize(width: maxWidth, height: proposal.height)

        if cache.maxWidth != (proposal.width ?? .greatestFiniteMagnitude) || cache.itemSizes.count != subviews.count {
            updateCache(&cache, proposal: proposal, subviews: subviews)
        }

        var y: CGFloat = bounds.minY

        for row in cache.result.rows {
            let rowXOffset: CGFloat
            switch alignment {
            case .leading:
                rowXOffset = 0
            case .center:
                rowXOffset = max(0, (maxWidth - row.width) / 2)
            case .trailing:
                rowXOffset = max(0, maxWidth - row.width)
            }

            var x: CGFloat = bounds.minX + rowXOffset

            for (position, index) in row.indices.enumerated() {
                let measuredSize = cache.itemSizes[index]
                let placedWidth = min(measuredSize.width, maxWidth)
                let placedSize = CGSize(width: placedWidth, height: measuredSize.height)

                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: placedSize.width, height: placedSize.height)
                )

                x += placedSize.width
                if position < row.indices.count - 1 {
                    x += horizontalSpacing
                }
            }

            y += row.height + verticalSpacing
        }
    }
}
