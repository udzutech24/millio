import Testing
@testable import millio

/// Баг 1: новый кредит создавался с балансом 0, потому что «Остаток долга» — отдельное поле,
/// которое молчаливо оставалось пустым, пока пользователь не тронул его руками. Первый круг
/// фикса гасил автосинк НАВСЕГДА при любом расхождении, включая полностью пустое поле —
/// сценарий «ввёл цифру в остаток, стёр, заполнил сумму кредита» снова давал `remainingAmount = 0`.
/// Правило синка проверяется здесь без SwiftUI: `InlineCreditCreateForm` только вызывает эти функции.
struct RemainingAmountAutoSyncTests {

    // MARK: - shouldStopSyncing

    @Test("пустой остаток НЕ останавливает синк — даже если сумма кредита уже непустая (сам Баг 1)")
    func emptyRemainingNeverStopsSyncing() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "", principalText: "1000000") == false)
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "", principalText: "") == false)
    }

    @Test("остаток равен сумме кредита — синк не останавливается")
    func remainingEqualsPrincipalKeepsSyncing() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "1000000", principalText: "1000000") == false)
    }

    @Test("непустой остаток отличается от суммы кредита — это ручная правка, синк останавливается")
    func remainingDiffersFromPrincipalStopsSyncing() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "900000", principalText: "1000000") == true)
    }

    // MARK: - shouldResumeSyncing

    @Test("очистка поля — сигнал на возобновление синка")
    func clearingFieldResumesSyncing() {
        #expect(RemainingAmountAutoSync.shouldResumeSyncing(newText: "") == true)
        #expect(RemainingAmountAutoSync.shouldResumeSyncing(newText: "0") == false)
    }

    // MARK: - resolvedText — итоговое решение, которое зовёт InlineCreditCreateForm

    @Test("Баг 1, второй путь: очистили остаток, сумма кредита уже есть — остаток снэпается на сумму немедленно")
    func clearingRemainingWithKnownPrincipalSnapsBackImmediately() {
        let resolved = RemainingAmountAutoSync.resolvedText(
            afterEditingTo: "", principalText: "1000000", isCurrentlyAutoSynced: false
        )
        #expect(resolved.text == "1000000")
        #expect(resolved.isAutoSynced == true)
    }

    @Test("очистили остаток, сумма кредита тоже ещё пуста — снэпать нечего, остаток остаётся пустым, синк включается")
    func clearingRemainingWithoutPrincipalStaysEmpty() {
        let resolved = RemainingAmountAutoSync.resolvedText(
            afterEditingTo: "", principalText: "", isCurrentlyAutoSynced: false
        )
        #expect(resolved.text == "")
        #expect(resolved.isAutoSynced == true)
    }

    @Test("ручная правка на другое непустое значение — синк гасится, текст не трогаем")
    func manualEditToDifferentValueStopsSyncing() {
        let resolved = RemainingAmountAutoSync.resolvedText(
            afterEditingTo: "900000", principalText: "1000000", isCurrentlyAutoSynced: true
        )
        #expect(resolved.text == "900000")
        #expect(resolved.isAutoSynced == false)
    }

    @Test("автосинк уже гашен, остаток совпал с суммой случайно — состояние не включается обратно")
    func matchingValueWhileNotSyncedStaysManual() {
        let resolved = RemainingAmountAutoSync.resolvedText(
            afterEditingTo: "1000000", principalText: "1000000", isCurrentlyAutoSynced: false
        )
        #expect(resolved.text == "1000000")
        #expect(resolved.isAutoSynced == false)
    }
}
