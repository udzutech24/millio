import Testing
@testable import millio

/// Баг 1: новый кредит создавался с балансом 0, потому что «Остаток долга» — отдельное поле,
/// которое молчаливо оставалось пустым, пока пользователь не тронул его руками. Правило синка
/// проверяется здесь без SwiftUI: `InlineCreditCreateForm` только вызывает эту функцию.
struct RemainingAmountAutoSyncTests {
    @Test("пустой остаток совпадает с пустой суммой кредита — синк не останавливается")
    func emptyMatchesEmptyPrincipal() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "", principalText: "") == false)
    }

    @Test("остаток равен сумме кредита — синк не останавливается")
    func remainingEqualsPrincipalKeepsSyncing() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "1000000", principalText: "1000000") == false)
    }

    @Test("остаток отличается от суммы кредита — это ручная правка, синк останавливается")
    func remainingDiffersFromPrincipalStopsSyncing() {
        #expect(RemainingAmountAutoSync.shouldStopSyncing(afterEditingTo: "900000", principalText: "1000000") == true)
    }
}
