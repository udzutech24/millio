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
        syncPlannedPayment(accountID: accountID)
        return target
    }

    func delete(accountID: UUID) throws {
        for row in try existingRows(for: accountID) { context.delete(row) }
        syncPlannedPayment(accountID: accountID)
    }

    /// Плановая операция кредита синхронизируется ЗДЕСЬ, а не у каждого вызывающего: договор
    /// правят четыре экрана и импорт, и любой из них мог бы забыть — тогда инвариант «ровно одна
    /// незакрытая плановая операция» держался бы на дисциплине, а не на коде.
    ///
    /// Ошибка синхронизации не отменяет правку договора: невозможность починить план не должна
    /// мешать пользователю сохранить условия кредита. Расхождение уходит в лог и чинится
    /// следующим касанием договора.
    private func syncPlannedPayment(accountID: UUID) {
        do {
            try LoanPlannedPaymentScheduler.sync(accountID: accountID, context: context)
        } catch {
            AppLogger.log(
                .error,
                category: "AccountsCore",
                "Failed to sync loan planned payment: \(error.localizedDescription)"
            )
        }
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
