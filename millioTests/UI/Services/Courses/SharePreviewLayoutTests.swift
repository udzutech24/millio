import CoreGraphics
import Foundation
import Testing
@testable import millio

struct SharePreviewLayoutTests {

    @Test("При полном доступном размере карточка не сжимается")
    func cardScaleWithoutConstraintsIsFull() {
        let scale = SharePreviewLayout.cardScale(
            availableWidth: SharePreviewLayout.baseCardWidth,
            availableHeight: SharePreviewLayout.baseCardHeight
        )
        #expect(scale == 1.0)
    }

    @Test("Высота предпросмотра уменьшается на высоту клавиатуры и контролов")
    func availableCardHeightShrinksWithKeyboard() {
        let availableHeight = SharePreviewLayout.availableCardHeight(containerHeight: 844, keyboardHeight: 320)
        #expect(availableHeight == 334)
    }

    @Test("Когда доступное место меньше исходного экрана карточка уменьшается")
    func cardScaleShrinksWithLimitedSpace() {
        let scale = SharePreviewLayout.cardScale(
            availableWidth: 240,
            availableHeight: 520
        )
        #expect(scale < 1.0)
    }

    @Test("Карточка не сжимается ниже минимального порога")
    func cardScaleRespectsLowerBound() {
        let scale = SharePreviewLayout.cardScale(
            availableWidth: 40,
            availableHeight: 80
        )
        #expect(scale == 0.32)
    }

    @Test("Размер превью следует вычисленному масштабу")
    func cardFrameSizeUsesScale() {
        let size = SharePreviewLayout.cardFrameSize(
            containerSize: CGSize(width: 390, height: 844),
            keyboardHeight: 320
        )
        #expect(size.height < SharePreviewLayout.baseCardHeight)
        #expect(size.width < SharePreviewLayout.baseCardWidth)
        #expect(size.height > 0)
    }
}
