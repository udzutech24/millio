//
//  RemainingAmountAutoSync.swift
//  millio
//

import Foundation

/// Правило «остаток долга по умолчанию равен сумме кредита, пока пользователь не тронул поле
/// вручную» — вынесено чистыми функциями, чтобы `InlineCreditCreateForm` не решала логику синка
/// сама в `body`, и чтобы граничные случаи (пусто, равно, отличается) проверялись без SwiftUI.
enum RemainingAmountAutoSync {
    /// `true`, если правку в «Остаток долга» пора считать осознанным выбором пользователя и
    /// прекратить тянуть значение из суммы кредита. Пустое поле — НЕ ручная правка (см.
    /// `shouldResumeSyncing`): иначе пользователь, очистивший остаток, навсегда гасил синк, и
    /// новый кредит открывался с балансом 0 при непустой сумме кредита (Баг 1, первый заход).
    static func shouldStopSyncing(afterEditingTo newText: String, principalText: String) -> Bool {
        !newText.isEmpty && newText != principalText
    }

    /// `true`, если пользователь стёр «Остаток долга» — синк пора включить обратно. Меняет ТОЛЬКО
    /// флаг `isRemainingAmountAutoSynced`, саму строку поля не трогает.
    ///
    /// До этого фикса `InlineCreditCreateForm` в своём `onChange(of: remainingAmountText)` при
    /// пустом поле сразу писала `remainingAmountText` обратно суммой кредита — на последнем стёртом
    /// символе поле мгновенно заполнялось «1 000 000», и следующая набранная цифра дописывалась ей
    /// в хвост через `AmountTextField` (raw+display пересборка): «1 000 000» + «6» → «1 000 000 006»
    /// вместо «600 000» (Баг 1, второй заход — очистить остаток и ввести новую сумму стало
    /// невозможно). Подстановка суммы кредита при пустом остатке теперь происходит только в момент
    /// чтения данных формы — см. `resolvedRemainingAmount`.
    static func shouldResumeSyncing(newText: String) -> Bool {
        newText.isEmpty
    }

    /// Значение, которое реально уходит в `openingBalance` (`InlineCreditCreateForm.getCreditData()`).
    /// Пустой или нечитаемый текст остатка — НЕ повод создать кредит на 0 ₽, пока сумма кредита
    /// известна: подставляем `principalAmount`. Явно введённый «0» — осознанный выбор пользователя
    /// (например, кредит уже полностью погашен) и НЕ переопределяется суммой кредита.
    static func resolvedRemainingAmount(text: String, principalAmount: Double) -> Double {
        AmountInputFormatter.parse(text) ?? principalAmount
    }
}
