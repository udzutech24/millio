import Foundation
import SwiftData

/// SwiftData-адаптеры reconciliation (Track B, B2b). @ModelActor → весь merge off-main
/// (митигация B1b №7: не блокировать main). Guest читается в Sendable-вход, user пишется
/// в собственном контексте актора с единственным save.

/// Читает guest-стор в Sendable `GuestMergeInput` на фоновом executor'е.
@ModelActor
actor ScopeGuestReader {
    func read() throws -> GuestMergeInput {
        try ScopeMergeReader.readGuestInput(context: modelContext)
    }

    func snapshot() throws -> ScopeSideSnapshot {
        try ScopeMergeReader.snapshot(context: modelContext)
    }
}

/// Применяет merge к user-стору в собственном контексте.
@ModelActor
actor ScopeMergeWorker {

    func snapshot() throws -> ScopeSideSnapshot {
        try ScopeMergeReader.snapshot(context: modelContext)
    }

    /// Импорт легаси + дедуп + копия new-core → sanity-abort → ЕДИНСТВЕННЫЙ save.
    /// Прерывание до save (throw/краш) не оставляет частичного состояния: контекст отбрасывается,
    /// на диск ничего не попадает; повторный запуск идемпотентен (митигации B1b №5, №7).
    func apply(
        input: GuestMergeInput,
        transactionTargets: [ScopeFingerprint: Int]
    ) throws -> ScopeMergeWorkerResult {
        let userPre = try ScopeMergeReader.counts(context: modelContext)

        try DataRepository.importAllData(input.legacyData, into: modelContext, save: false)
        try ScopeMergeDedup.dedupe(context: modelContext, transactionTargets: transactionTargets)
        let coreAdded = try ScopeMergeDedup.copyNewCore(input.newCore, into: modelContext)

        let merged = try ScopeMergeReader.counts(context: modelContext)
        // Sanity-abort: слитый набор не может превышать сумму сторон. Нарушение = логика merge поехала —
        // не сохраняем, контекст отбрасывается (митигация B1b №7).
        for (model, mergedCount) in merged {
            let bound = (userPre[model] ?? 0) + (input.snapshot.modelCounts[model] ?? 0)
            if mergedCount > bound {
                throw ScopeMergeError.sanityViolation(model: model, merged: mergedCount, bound: bound)
            }
        }

        try modelContext.save() // ЕДИНСТВЕННЫЙ save (митигация B1b №5)

        let legacyAccounts = Self.added(merged, userPre, [
            ScopeMergeReader.Model.card, ScopeMergeReader.Model.credit,
            ScopeMergeReader.Model.investment, ScopeMergeReader.Model.financeAccount
        ])
        let transactions = Self.added(merged, userPre, [ScopeMergeReader.Model.transaction])
        return ScopeMergeWorkerResult(
            accountsAdded: legacyAccounts + coreAdded.accountsAdded,
            transactionsAdded: transactions + coreAdded.eventsAdded
        )
    }

    private static func added(_ merged: [String: Int], _ pre: [String: Int], _ models: [String]) -> Int {
        models.reduce(0) { acc, model in
            acc + max(0, (merged[model] ?? 0) - (pre[model] ?? 0))
        }
    }
}
