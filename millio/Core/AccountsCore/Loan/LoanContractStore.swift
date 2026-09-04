import Foundation
import SwiftData

/// Единственная точка доступа к `LoanContract`: выборка и идемпотентный upsert по `accountID`.
///
/// Прямые `context.fetch(FetchDescriptor<LoanContract>())` по коду запрещены по той же причине,
/// что у `AccountAppearanceStore`: `@Attribute(.unique)` в проекте недоступен (CloudKit), поэтому
/// restore/merge может внести вторую строку на тот же счёт, и «победителя» надо выбирать в одном
/// месте, а не в каждом вызывающем.
struct LoanContractStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    /// Договор счёта. При дублях побеждает самый свежий по `updatedAt`.
    func contract(for accountID: UUID) throws -> LoanContract? {
        try existingRows(for: accountID).first
    }

    /// Идемпотентный upsert: два вызова на один `accountID` дают одну строку.
    @discardableResult
    func upsert(accountID: UUID, _ mutate: (LoanContract) -> Void) throws -> LoanContract {
        let rows = try existingRows(for: accountID)
        let target: LoanContract
        if let existing = rows.first {
            target = existing
            // Схлопываем дубли по ходу дела — иначе следующее чтение снова выберет «победителя»
            // произвольно и правка условий визуально «не применится».
            for duplicate in rows.dropFirst() { context.delete(duplicate) }
        } else {
            target = LoanContract(accountID: accountID)
            context.insert(target)
        }
        mutate(target)
        target.updatedAt = Date()
        return target
    }

    func delete(accountID: UUID) throws {
        for row in try existingRows(for: accountID) { context.delete(row) }
    }

    /// Строки, отсортированные так, что первой идёт самая свежая — тот же победитель, что в `upsert`.
    private func existingRows(for accountID: UUID) throws -> [LoanContract] {
        var descriptor = FetchDescriptor<LoanContract>(
            predicate: #Predicate<LoanContract> { $0.accountID == accountID }
        )
        descriptor.sortBy = [SortDescriptor(\.updatedAt, order: .reverse)]
        return try context.fetch(descriptor)
    }
}
