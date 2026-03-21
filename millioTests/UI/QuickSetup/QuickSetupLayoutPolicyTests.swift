import XCTest
@testable import millio

final class QuickSetupLayoutPolicyTests: XCTestCase {
    func testContentBottomPaddingUsesDefaultSpacingWithoutKeyboard() {
        XCTAssertEqual(
            QuickSetupLayout.contentBottomPadding(keyboardOverlap: 0),
            QuickSetupLayout.defaultContentBottomPadding
        )
    }

    func testContentBottomPaddingAddsKeyboardOverlap() {
        XCTAssertEqual(
            QuickSetupLayout.contentBottomPadding(keyboardOverlap: 216),
            QuickSetupLayout.defaultContentBottomPadding + 216
        )
    }

    func testKeyboardOverlapSubtractsSafeAreaInset() {
        let overlap = QuickSetupLayout.keyboardOverlap(
            screenHeight: 844,
            keyboardFrame: CGRect(x: 0, y: 510, width: 390, height: 334),
            safeAreaBottom: 34
        )

        XCTAssertEqual(overlap, 300)
    }

    func testKeyboardOverlapIsZeroWhenKeyboardIsHidden() {
        XCTAssertEqual(
            QuickSetupLayout.keyboardOverlap(
                screenHeight: 844,
                keyboardFrame: .zero,
                safeAreaBottom: 34
            ),
            0
        )
    }
}
