import CoreGraphics

struct SharePreviewLayout {
    static let baseCardHeight: CGFloat = 540

    private static let minCardScale: CGFloat = 0.62
    // Includes title chip, multiline note field, nav bar and bottom spacing.
    private static let reservedControlsHeight: CGFloat = 270

    static func cardScale(containerHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        let safeContainerHeight = max(0, containerHeight)
        let safeKeyboardHeight = max(0, keyboardHeight)
        let availableForCard = max(0, safeContainerHeight - safeKeyboardHeight - reservedControlsHeight)
        let rawScale = availableForCard / baseCardHeight
        return min(1.0, max(minCardScale, rawScale))
    }

    static func cardFrameHeight(containerHeight: CGFloat, keyboardHeight: CGFloat) -> CGFloat {
        baseCardHeight * cardScale(containerHeight: containerHeight, keyboardHeight: keyboardHeight)
    }
}
