import Foundation
import Testing
@testable import millio

struct SharePreviewLayoutTests {

    @Test("Без клавиатуры карточка не сжимается")
    func cardScaleWithoutKeyboardIsFull() {
        let scale = SharePreviewLayout.cardScale(containerHeight: 844, keyboardHeight: 0)
        #expect(scale == 1.0)
    }

    @Test("При появлении клавиатуры карточка уменьшается")
    func cardScaleShrinksWithKeyboard() {
        let scale = SharePreviewLayout.cardScale(containerHeight: 844, keyboardHeight: 320)
        #expect(scale < 1.0)
    }

    @Test("Карточка не сжимается ниже минимального порога")
    func cardScaleRespectsLowerBound() {
        let scale = SharePreviewLayout.cardScale(containerHeight: 500, keyboardHeight: 420)
        #expect(scale == 0.62)
    }

    @Test("Высота карточки следует вычисленному масштабу")
    func cardFrameHeightUsesScale() {
        let height = SharePreviewLayout.cardFrameHeight(containerHeight: 844, keyboardHeight: 320)
        #expect(height < SharePreviewLayout.baseCardHeight)
        #expect(height > 0)
    }
}
