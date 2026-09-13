import Testing
@testable import millio

/// Баг 1: новый кредит создавался с балансом 0, потому что «Остаток долга» — отдельное поле,
/// которое молчаливо оставалось пустым, пока пользователь не тронул его руками.
///
/// Первый заход фикса гасил автосинк НАВСЕГДА при любом расхождении, включая полностью пустое
/// поле — сценарий «ввёл цифру в остаток, стёр, заполнил сумму кредита» снова давал
/// `remainingAmount = 0`. Второй заход это починил, но взамен стал переписывать
/// `remainingAmountText` прямо в своём же `onChange` при пустом поле — на последнем стёртом
/// символе поле мгновенно заполнялось суммой кредита, и следующая набранная цифра дописывалась
/// в её хвост («1 000 000» + «6» → «1 000 000 006» вместо «600 000»), то есть очистить остаток и
/// ввести новую сумму стало физически невозможно (ревью round 2). Правило синка проверяется здесь
/// без SwiftUI: `InlineCreditCreateForm` только вызывает эти функции.
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

    @Test("очистка поля — сигнал на возобновление синка (флаг, не текст)")
    func clearingFieldResumesSyncing() {
        #expect(RemainingAmountAutoSync.shouldResumeSyncing(newText: "") == true)
        #expect(RemainingAmountAutoSync.shouldResumeSyncing(newText: "0") == false)
    }

    // MARK: - resolvedRemainingAmount — то, что реально уходит в openingBalance

    @Test("Баг 1, буква требования: пустой остаток при известной сумме кредита — подставляем сумму, НЕ 0")
    func emptyTextWithKnownPrincipalResolvesToPrincipal() {
        let resolved = RemainingAmountAutoSync.resolvedRemainingAmount(text: "", principalAmount: 1_000_000)
        #expect(resolved == 1_000_000)
    }

    @Test("пустой остаток и пустая сумма кредита — подставлять нечего, результат 0 (форма действительно пуста)")
    func emptyTextWithoutPrincipalResolvesToZero() {
        let resolved = RemainingAmountAutoSync.resolvedRemainingAmount(text: "", principalAmount: 0)
        #expect(resolved == 0)
    }

    @Test("явный «0» в остатке при известной сумме кредита — осознанный выбор пользователя, сумму НЕ подставляем")
    func explicitZeroWithKnownPrincipalStaysZero() {
        let resolved = RemainingAmountAutoSync.resolvedRemainingAmount(text: "0", principalAmount: 1_000_000)
        #expect(resolved == 0)
    }

    @Test("непустой остаток — читаем как есть, сумму кредита не подмешиваем")
    func nonEmptyTextResolvesToItself() {
        let resolved = RemainingAmountAutoSync.resolvedRemainingAmount(text: "600000", principalAmount: 1_000_000)
        #expect(resolved == 600_000)
    }
}
