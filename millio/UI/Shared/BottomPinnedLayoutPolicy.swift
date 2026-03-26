import CoreGraphics

/// Унифицирует нижние отступы для экранов с закреплёнными снизу действиями.
///
/// Ключевое правило:
/// - `safeAreaInset(edge: .bottom)` сам резервирует высоту нижнего блока, поэтому
///   контенту нужен только компактный финальный отступ.
/// - overlay-кнопки в `ZStack` место не резервируют, поэтому под них считаем
///   реальный clearance из размера оверлея и нижнего внешнего отступа.
enum BottomPinnedLayoutPolicy {
    static let compactContentBottomPadding: CGFloat = 24
    static let defaultOverlayClearance: CGFloat = 16
    static let insetSpacing: CGFloat = 0

    static func scrollContentBottomPaddingForSafeAreaInset(
        minimumSpacing: CGFloat = compactContentBottomPadding
    ) -> CGFloat {
        minimumSpacing
    }

    static func scrollContentBottomPaddingForOverlay(
        overlayHeight: CGFloat,
        overlayBottomPadding: CGFloat,
        additionalClearance: CGFloat = defaultOverlayClearance,
        minimumSpacing: CGFloat = compactContentBottomPadding
    ) -> CGFloat {
        max(minimumSpacing, overlayHeight + overlayBottomPadding + additionalClearance)
    }
}
