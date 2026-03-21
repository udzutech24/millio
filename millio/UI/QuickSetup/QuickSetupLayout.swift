import CoreGraphics
import Foundation

/// Centralizes spacing decisions for the quick setup flow so keyboard behavior
/// stays predictable across small and tall screens.
enum QuickSetupLayout {
    static let defaultContentBottomPadding: CGFloat = 20

    static func contentBottomPadding(keyboardOverlap: CGFloat) -> CGFloat {
        defaultContentBottomPadding + max(0, keyboardOverlap)
    }

    static func keyboardOverlap(
        screenHeight: CGFloat,
        keyboardFrame: CGRect,
        safeAreaBottom: CGFloat
    ) -> CGFloat {
        guard keyboardFrame != .zero else { return 0 }
        let rawOverlap = max(0, screenHeight - keyboardFrame.minY)
        return max(0, rawOverlap - safeAreaBottom)
    }
}
