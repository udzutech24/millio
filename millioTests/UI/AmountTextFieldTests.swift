import Foundation
import Testing
@testable import millio

/// Round-trip raw↔display для обёртки `AmountTextField`. Проверяем ту же чистую логику,
/// что вызывается в `onChange` рантайма (static canonical/formatted).
struct AmountTextFieldTests {
    @Test("empty string stays empty in both directions")
    func emptyRoundTrip() {
        #expect(AmountTextField.canonical(from: "") == "")
        #expect(AmountTextField.formatted(from: "") == "")
    }

    @Test("leading zero is trimmed to canonical, display matches")
    func leadingZero() {
        let canonical = AmountTextField.canonical(from: "01000")
        #expect(canonical == "1000")
        #expect(AmountTextField.formatted(from: canonical) == "1 000")
    }

    @Test("bare separator is normalized to 0-prefixed canonical")
    func bareSeparator() {
        // Ввод одного разделителя ("," или ".") даёт "0." — незавершённая дробь при печати.
        #expect(AmountTextField.canonical(from: ".") == "0.")
        #expect(AmountTextField.canonical(from: ",") == "0.")
        #expect(AmountTextField.formatted(from: "0.") == "0.")
    }

    @Test("fraction longer than maxFractionDigits is truncated")
    func fractionTruncation() {
        let canonical = AmountTextField.canonical(from: "10.999", maxFractionDigits: 2)
        #expect(canonical == "10.99")
        #expect(AmountTextField.formatted(from: canonical, maxFractionDigits: 2) == "10.99")
    }

    @Test("display→canonical→display is idempotent on grouped value")
    func idempotentRoundTrip() {
        let canonical = AmountTextField.canonical(from: "1 234 567.5")
        #expect(canonical == "1234567.5")
        let display = AmountTextField.formatted(from: canonical)
        #expect(display == "1 234 567.5")
        // повторная прогонка через canonical не меняет результат
        #expect(AmountTextField.canonical(from: display) == canonical)
    }

    @Test("comma decimal separator is normalized to canonical dot")
    func commaNormalized() {
        #expect(AmountTextField.canonical(from: "10000,5") == "10000.5")
    }
}
