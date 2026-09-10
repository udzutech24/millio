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
    /// прекратить тянуть значение из суммы кредита. Пустое поле — НЕ ручная правка (см.
    /// `shouldResumeSyncing`): иначе пользователь, очистивший остаток, навсегда гасил синк, и
    /// новый кредит открывался с балансом 0 при непустой сумме кредита (Баг 1, второй путь).
    static func shouldStopSyncing(afterEditingTo newText: String, principalText: String) -> Bool {
        !newText.isEmpty && newText != principalText
    }

    /// `true`, если пользователь стёр «Остаток долга» — синк пора включить обратно, а не оставлять
    /// погашенным первой же случайной очисткой поля.
    static func shouldResumeSyncing(newText: String) -> Bool {
        newText.isEmpty
    }

    /// Итоговое значение поля и флага синка после правки «Остатка долга» — единая точка решения,
    /// которую вызывает `InlineCreditCreateForm.onChange(of: remainingAmountText)`.
    /// Если пользователь стёр остаток, а сумма кредита УЖЕ известна — подставляем её немедленно,
    /// не дожидаясь следующего изменения условий договора: иначе воспроизводится ровно тот
    /// сценарий, который не поймал первый круг фикса — пользователь очистил остаток и сумму
    /// кредита больше не трогает, поле остаётся пустым до следующего действия.
    static func resolvedText(
        afterEditingTo newText: String,
        principalText: String,
        isCurrentlyAutoSynced: Bool
    ) -> (text: String, isAutoSynced: Bool) {
        if shouldResumeSyncing(newText: newText) {
            return principalText.isEmpty ? (newText, true) : (principalText, true)
        }
        if shouldStopSyncing(afterEditingTo: newText, principalText: principalText) {
            return (newText, false)
        }
        return (newText, isCurrentlyAutoSynced)
    }
}
