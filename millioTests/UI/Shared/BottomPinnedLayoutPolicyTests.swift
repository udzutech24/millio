import CoreGraphics
import Testing
@testable import millio

struct BottomPinnedLayoutPolicyTests {
    @Test("safeAreaInset не требует двойного нижнего резерва в ScrollView")
    func safeAreaInsetUsesCompactContentPadding() {
        #expect(
            BottomPinnedLayoutPolicy.scrollContentBottomPaddingForSafeAreaInset()
                == BottomPinnedLayoutPolicy.compactContentBottomPadding
        )
    }

    @Test("overlay-контролы резервируют место по своей реальной высоте")
    func overlayPaddingUsesOverlayFootprint() {
        let padding = BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: 64,
            overlayBottomPadding: 20
        )

        #expect(
            padding
                == 64 + 20 + BottomPinnedLayoutPolicy.defaultOverlayClearance
        )
    }

    @Test("overlay-контролы не могут уменьшить нижний отступ ниже компактного минимума")
    func overlayPaddingKeepsCompactMinimum() {
        let padding = BottomPinnedLayoutPolicy.scrollContentBottomPaddingForOverlay(
            overlayHeight: 0,
            overlayBottomPadding: 0
        )

        #expect(padding == BottomPinnedLayoutPolicy.compactContentBottomPadding)
    }
}
