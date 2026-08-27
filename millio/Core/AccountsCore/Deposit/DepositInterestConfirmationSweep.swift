import Foundation
import SwiftData

/// Авто-подтверждение наступивших начислений по вкладам (план
/// `2026-08-26__deposit-confirmed-balance-unification.md`, Ф1.5, вариант A владельца).
///
/// Ручного пути подтверждения в проде нет: `DepositOperationCoordinator.confirmInterest`
/// имеет call sites только в тестах. Без этой развёртки подтверждённый баланс вклада замер бы
/// навсегда и мог бы расти только ручной корректировкой.
@MainActor
enum DepositInterestConfirmationSweep {

    /// Префикс подтверждённого начисления. Специально НЕ `deposit-interest:` — по тому префиксу
    /// событие считается прогнозом (`DepositConfirmedBalanceResolver.isGeneratedInterest`),
    /// а `DepositOperationCoordinator.normalizedOperationID` запрещает его как operationID.
    static let confirmedSourcePrefix = "deposit-interest-confirmed:"

    static func confirmedSourceID(accountID: UUID, date: Date) -> String {
        "\(confirmedSourcePrefix)\(accountID.uuidString):\(AccountEvent.dayKey(for: date))"
    }

    /// Прогнозное начисление с наступившей датой выплаты (`date <= asOf`) становится подтверждённым.
    /// Идемпотентна: подтверждённое событие перестаёт быть прогнозным, и повторный прогон его не видит.
    /// Возвращает число подтверждённых событий.
    @discardableResult
    static func run(context: ModelContext, asOf: Date = Date()) -> Int {
        let depositKindRaw = AccountKind.deposit.rawValue
        let descriptor = FetchDescriptor<Account>(
            predicate: #Predicate<Account> { $0.kindRaw == depositKindRaw && $0.archivedAt == nil }
        )
        guard let accounts = try? context.fetch(descriptor), !accounts.isEmpty else { return 0 }

        // Один широкий фетч вместо запроса на каждый счёт в цикле — тот же приём, что в
        // `DepositInterestScheduler.extendActiveDepositHorizons`.
        let allEvents = (try? context.fetch(FetchDescriptor<AccountEvent>())) ?? []
        let eventsByAccount = Dictionary(grouping: allEvents) { $0.account?.id }

        let service = AccountsCoreService(modelContext: context)
        var confirmedCount = 0
        var didChange = false

        for account in accounts {
            let events = eventsByAccount[account.id] ?? []

            // Корректировка баланса выставляет АБСОЛЮТНОЕ значение и считает дельту от подтверждённых
            // событий (`DepositOperationCoordinator.adjustBalance`). Значит любой прогноз с датой не
            // позже корректировки ею уже поглощён: подтвердить его задним числом = вернуть в баланс
            // сумму, которую пользователь только что списал (реальный кейс «Альфа 12%»: 13 000 000
            // снова превратились бы в 13 141 138). Такой прогноз не подтверждается, а удаляется —
            // это производные данные, перекрытые более поздней корректировкой, ровно как в
            // `rebuildFutureSchedule` для прогнозов после даты корректировки.
            let lastCorrectionDate = events.filter { $0.type == .adjustment }.map(\.date).max()

            var earliestTouched: Date?
            for event in events
            where DepositConfirmedBalanceResolver.isGeneratedInterest(event, accountID: account.id)
                && event.date <= asOf {
                if let lastCorrectionDate, event.date <= lastCorrectionDate {
                    context.delete(event)
                } else {
                    event.sourceTransactionID = confirmedSourceID(accountID: account.id, date: event.date)
                    confirmedCount += 1
                }
                didChange = true
                earliestTouched = min(earliestTouched ?? event.date, event.date)
            }

            // Снапшот-кэш этих дней посчитан по старой ленте — после Ф1 подтверждение меняет
            // значение checkpoint-а, а удаление меняет и сам набор дней.
            if let earliestTouched {
                service.invalidateSnapshotCache(for: account, from: earliestTouched)
            }
        }

        guard didChange else { return 0 }
        do {
            try context.save()
        } catch {
            context.rollback()
            AppLogger.log(.error, category: "AccountsCore", "Не удалось подтвердить начисления по вкладам: \(error)")
            return 0
        }
        return confirmedCount
    }
}
