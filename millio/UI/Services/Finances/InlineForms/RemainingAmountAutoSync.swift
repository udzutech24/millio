//
//  RemainingAmountAutoSync.swift
//  millio
//

import Foundation

/// Правило «остаток долга по умолчанию равен сумме кредита, пока пользователь не тронул поле
/// вручную» — вынесено чистой функцией, чтобы `InlineCreditCreateForm` не решала логику синка
/// сам `View.body`, и чтобы граничные случаи (пусто, равно, отличается) проверялись без SwiftUI.
enum RemainingAmountAutoSync {
    /// `true`, если правку в «Остаток долга» пора считать осознанным выбором пользователя и
    /// прекратить тянуть значение из суммы кредита. Совпадение с текущей суммой (в том числе
    /// оба пустые) — это ещё не ручная правка: сумма могла просто обновиться сама.
    static func shouldStopSyncing(afterEditingTo newText: String, principalText: String) -> Bool {
        newText != principalText
    }
}
