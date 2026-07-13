//
//  AmountTextField.swift
//  millio
//

import SwiftUI

/// Переиспользуемое поле ввода денежной суммы с живым форматированием разрядов.
/// Наружу отдаёт канонический raw-decimal (разделитель "."), внутри держит
/// отформатированную display-строку с пробелами-разрядами. Семантика raw+display
/// скопирована из `CashflowTransactionEditorView` (эталонный протестированный паттерн):
/// реассайн происходит только при реальном отличии — иначе курсор прыгает.
struct AmountTextField: View {
    let placeholder: String
    @Binding var value: String
    var maxFractionDigits: Int = AmountInputFormatter.defaultFractionDigits
    /// Размер шрифта по длине display-текста (нужен сцене Cashflow, где шрифт суммы
    /// зависит от количества символов). `nil` — шрифт задаёт вызывающая сторона.
    var font: ((String) -> Font)?

    @State private var displayText: String = ""

    init(
        placeholder: String,
        value: Binding<String>,
        maxFractionDigits: Int = AmountInputFormatter.defaultFractionDigits,
        font: ((String) -> Font)? = nil
    ) {
        self.placeholder = placeholder
        self._value = value
        self.maxFractionDigits = maxFractionDigits
        self.font = font
    }

    var body: some View {
        let field = TextField(placeholder, text: Binding(
            get: { displayText },
            set: { displayText = $0 }
        ))
        .keyboardType(.decimalPad)
        .onAppear { syncDisplayFromValue(value) }
        .onChange(of: displayText) { _, newValue in
            let canonical = Self.canonical(from: newValue, maxFractionDigits: maxFractionDigits)
            let formatted = Self.formatted(from: canonical, maxFractionDigits: maxFractionDigits)
            if newValue != formatted { displayText = formatted }
            if value != canonical { value = canonical }
        }
        .onChange(of: value) { _, newValue in
            // Внешнее (программное) изменение raw — например prefill в edit-режиме.
            // Пересобираем display только если он расходится с новым каноническим value,
            // иначе затрём то, что пользователь как раз печатает.
            let currentCanonical = Self.canonical(from: displayText, maxFractionDigits: maxFractionDigits)
            if currentCanonical != newValue { syncDisplayFromValue(newValue) }
        }

        if let font {
            field.font(font(displayText))
        } else {
            field
        }
    }

    private func syncDisplayFromValue(_ raw: String) {
        let formatted = Self.formatted(from: raw, maxFractionDigits: maxFractionDigits)
        if displayText != formatted { displayText = formatted }
    }

    // MARK: - Чистая логика raw↔display (тестируемо, идентично рантайму)

    /// display-строка (или сырой ввод) → канонический raw ("."-разделитель, без разрядов).
    static func canonical(from text: String, maxFractionDigits: Int = AmountInputFormatter.defaultFractionDigits) -> String {
        AmountInputFormatter.sanitize(text, maxFractionDigits: maxFractionDigits)
    }

    /// raw (или сырой ввод) → display-строка с разрядами.
    static func formatted(from text: String, maxFractionDigits: Int = AmountInputFormatter.defaultFractionDigits) -> String {
        AmountInputFormatter.display(text, maxFractionDigits: maxFractionDigits)
    }
}
