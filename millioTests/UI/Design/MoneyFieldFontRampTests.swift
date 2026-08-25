import Foundation
import SwiftUI
import Testing
import UIKit
@testable import millio

/// Ступени шрифта поля суммы проверяем РЕАЛЬНЫМИ метриками SF, а не «на глаз»: баг был именно в
/// том, что число не помещалось в поле, а `TextField` его прокручивал вместо сжатия.
struct MoneyFieldFontRampTests {
    /// Худший из двух экранов — создание счёта на 390pt (у него отступы шире, чем у правки):
    /// 390 − 40 (отступы экрана) − 32 (padding карточки) − 24 (два зазора HStack) − 1 (разделитель)
    /// − 96 (колонка ставки) − 8 (зазор до валюты) − 62 (чип валюты с 4-символьным кодом) = 127pt.
    private static let amountFieldWidth: CGFloat = 127

    /// До 11 непробельных символов включительно (99 млрд, либо 999 млн с копейками) ступень обязана
    /// уместить строку сама. Дальше — уже не «реалистичный ввод» из репорта, там подстраховывает
    /// `minimumScaleFactor`: опускать токен ниже 16pt ради триллионов бессмысленно.
    private static let maxFittingGlyphs = 11

    private func width(_ text: String, step: MoneyFieldFontRamp) -> CGFloat {
        let weight: UIFont.Weight = step.weight == .bold ? .bold : .semibold
        let font = UIFont.systemFont(ofSize: step.pointSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// Ровно то, что видит пользователь: строка собирается тем же форматтером, что и в поле.
    private func display(digits: Int, fractionDigits: Int = 0) -> String {
        let raw = String(repeating: "9", count: digits)
            + (fractionDigits == 0 ? "" : "." + String(repeating: "9", count: fractionDigits))
        return AmountTextField.formatted(from: raw)
    }

    private func glyphs(_ text: String) -> Int {
        text.filter { !$0.isWhitespace }.count
    }

    @Test("любой реалистичный ввод помещается в поле суммы целиком")
    func everyRealisticAmountFitsTheField() {
        for digits in 1...11 {
            for fractionDigits in 0...2 {
                let text = display(digits: digits, fractionDigits: fractionDigits)
                guard glyphs(text) <= Self.maxFittingGlyphs else { continue }
                let step = MoneyFieldFontRamp.step(for: text)
                let measured = width(text, step: step)
                #expect(
                    measured <= Self.amountFieldWidth,
                    "«\(text)»: \(measured)pt > \(Self.amountFieldWidth)pt при \(step.pointSize)pt"
                )
            }
        }
    }

    @Test("копейки учитываются наравне с цифрами")
    func fractionSeparatorCountsTowardsTheStep() {
        // Регрессия замера: «9 999.99» шире, чем «999 999», хотя цифр столько же —
        // точка по ширине почти равна цифре, а разделитель разрядов заметно уже.
        #expect(MoneyFieldFontRamp.step(for: "9 999.99") != .display)
        #expect(MoneyFieldFontRamp.step(for: "999 999") == .display)
    }

    @Test("шрифт не растёт по мере удлинения числа")
    func rampIsMonotonic() {
        var previous = MoneyFieldFontRamp.step(for: display(digits: 1)).pointSize
        for digits in 2...Self.maxFittingGlyphs {
            let current = MoneyFieldFontRamp.step(for: display(digits: digits)).pointSize
            #expect(current <= previous)
            previous = current
        }
    }

    @Test("регрессия: крупные суммы больше не рисуются 30pt-токеном")
    func largeAmountsLeaveDisplayToken() {
        // Репорт с устройства: «40 000 000» уезжало за границу поля при millioDisplay.
        #expect(MoneyFieldFontRamp.step(for: "40 000 000") != .display)
        #expect(MoneyFieldFontRamp.step(for: "1 000 000 000") == .headline)
        // Короткие суммы остаются крупными — это основной сценарий, его портить нельзя.
        #expect(MoneyFieldFontRamp.step(for: "100 000") == .display)
        #expect(MoneyFieldFontRamp.font(for: "") == .millioDisplay)
    }
}
