import CoreGraphics

struct SharePreviewLayout {
    static let baseCardWidth: CGFloat = 390
    static let baseCardHeight: CGFloat = 844

    private static let minCardScale: CGFloat = 0.32
    // Includes title chip, multiline note field, nav bar and bottom spacing.
    private static let reservedControlsHeight: CGFloat = 190
    private static let previewHorizontalPadding: CGFloat = 28

    static func availableCardHeight(containerHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        let safeContainerHeight = max(0, containerHeight)
        let safeKeyboardHeight = max(0, keyboardHeight)
        return max(0, safeContainerHeight - safeKeyboardHeight - reservedControlsHeight)
    }

    static func availableCardWidth(containerWidth: CGFloat) -> CGFloat {
        max(0, containerWidth - previewHorizontalPadding)
    }

    static func cardScale(availableWidth: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let safeAvailableWidth = max(0, availableWidth)
        let safeAvailableHeight = max(0, availableHeight)
        let rawScale = min(safeAvailableWidth / baseCardWidth, safeAvailableHeight / baseCardHeight)
        return min(1.0, max(minCardScale, rawScale))
    }

    static func cardScale(containerSize: CGSize, keyboardHeight: CGFloat) -> CGFloat {
        cardScale(
            availableWidth: availableCardWidth(containerWidth: containerSize.width),
            availableHeight: availableCardHeight(containerHeight: containerSize.height, keyboardHeight: keyboardHeight)
        )
    }

    static func cardFrameSize(containerSize: CGSize, keyboardHeight: CGFloat) -> CGSize {
        let scale = cardScale(containerSize: containerSize, keyboardHeight: keyboardHeight)
        return CGSize(width: baseCardWidth * scale, height: baseCardHeight * scale)
    }
}
