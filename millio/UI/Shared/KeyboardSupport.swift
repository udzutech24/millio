//
//  KeyboardSupport.swift
//  millio
//

import SwiftUI
import UIKit

enum InputDismissalSupport {
    static func dismissActiveResponder() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

extension View {
    func dismissKeyboardOnTap() -> some View {
        onTapGesture {
            InputDismissalSupport.dismissActiveResponder()
        }
    }
}

/// Задержка автофокуса в bottom-sheet: на первом кадре UIKit ещё не отдал листу responder-цепочку,
/// и запрошенный сразу фокус теряется — клавиатура не поднимается, нужен лишний тап.
private let sheetAutofocusDelayNanoseconds: UInt64 = 350_000_000

extension View {
    /// Поднимает клавиатуру сразу при открытии листа. `@FocusState` презентующего экрана через
    /// границу презентации не работает — состояние должно жить ВНУТРИ листа, а фокус
    /// запрашиваться после анимации презентации.
    func autofocusAfterPresentation(_ isFocused: FocusState<Bool>.Binding) -> some View {
        task {
            try? await Task.sleep(nanoseconds: sheetAutofocusDelayNanoseconds)
            isFocused.wrappedValue = true
        }
    }
}
