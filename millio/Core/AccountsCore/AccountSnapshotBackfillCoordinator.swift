import Foundation
import SwiftData

/// Разовая (per-scope) фоновая пересборка снапшот-кэша `AccountDailySnapshot` для ВСЕХ счетов
/// ядра — от даты первого события каждого счёта до сегодня. Источник данных для периодов
/// «1Г»/«Всё» графика деталей счёта (Open Question №6, `specs/2026-07-05-account-detail-per-type.md`):
/// чтобы график не платил за реплей истории вживую при первом открытии экрана, кэш должен быть
/// прогрет ЗАРАНЕЕ, в фоне при старте приложения.
///
/// НЕ выполняет реплей сам — просто вызывает уже существующий `AccountSnapshotRebuilder.rebuild(upTo:)`
/// для каждого счёта. У `rebuild` уже есть нужное свойство: на «холодном» счёте без единого снапшота
/// он строит ВСЕ checkpoint-ы от первого события до `upTo` за один вызов (см. `AccountSnapshotRebuilder`
/// докстринг), поэтому координатор — это только перебор счетов + однократный per-scope триггер.
///
/// Дальнейшее поддержание кэша (новые события завтра/послезавтра) координатор НЕ обслуживает —
/// этим продолжает заниматься существующий инкрементальный путь `AccountsTotalsService.balance(for:on:)`,
/// вызываемый при любом обращении к тоталам/графику.
@MainActor
final class AccountSnapshotBackfillCoordinator {
    /// per-scope, НЕ глобальный ключ: холодный старт всегда создаёт первый `DIContainer` на
    /// guest-сторе (см. `DataIntegrityCleaner.archiveZeroQuantityInvestmentsIfNeeded`), и только потом
    /// второй — на реальном user-сторе через `rebindDataScope`. Общий на всё приложение флаг сгорел бы
    /// на почти пустом guest-сторе, и реальный user-стор с историей счетов никогда бы не забэкфиллился.
    /// v2 (Ф1 плана `2026-08-26__deposit-confirmed-balance-unification.md`): снапшоты, посчитанные
    /// по старой формуле, включают прогнозные начисления вкладов. `rebuild(upTo:)` их никогда бы не
    /// перегенерировал (`keepExisting: true` даёт ранний выход), а `rebuildAllAccounts` живёт только
    /// в дебаг-экране — поэтому нужен новый ключ флага и полная пересборка.
    private static let flagKeyPrefix = "migration.accountSnapshotBackfill.v2."

    private let modelContainer: ModelContainer
    private let defaults: UserDefaults
    private let nowProvider: () -> Date
    private var preparedScopes: Set<String> = []
    private var inFlight: [String: (id: UUID, task: Task<Int, Never>)] = [:]

    init(
        modelContainer: ModelContainer,
        defaults: UserDefaults = .standard,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.modelContainer = modelContainer
        self.defaults = defaults
        self.nowProvider = nowProvider
    }

    /// Запускает разовый бэкфилл для scope, если он ещё не выполнялся. Возвращает число
    /// обработанных счетов (0, если бэкфилл уже отмечен выполненным или счетов ядра ещё нет).
    @discardableResult
    func backfillIfNeeded(scopeIdentifier: String) async -> Int {
        if let current = inFlight[scopeIdentifier] {
            return await current.task.value
        }
        guard prepareIfNeeded(scopeIdentifier: scopeIdentifier) else { return 0 }

        let taskID = UUID()
        let task = Task { @MainActor [self] in
            await performBackfill(scopeIdentifier: scopeIdentifier)
        }
        inFlight[scopeIdentifier] = (taskID, task)
        let result = await task.value
        if inFlight[scopeIdentifier]?.id == taskID {
            inFlight.removeValue(forKey: scopeIdentifier)
        }
        preparedScopes.remove(scopeIdentifier)
        return result
    }

    /// Enters the durable readiness gate before a fire-and-forget task is scheduled. This closes
    /// the lifecycle window where the UI could publish a close after `.ready` but before the async
    /// backfill task got its first executor turn.
    @discardableResult
    func prepareIfNeeded(scopeIdentifier: String) -> Bool {
        let flagKey = Self.flagKeyPrefix + scopeIdentifier
        guard !defaults.bool(forKey: flagKey) else { return false }
        guard preparedScopes.insert(scopeIdentifier).inserted else { return true }

        HistoricalValuationReadinessCoordinator.shared.begin(
            scopeID: scopeIdentifier,
            operation: .backfill
        )
        return true
    }

    private func performBackfill(scopeIdentifier: String) async -> Int {
        let flagKey = Self.flagKeyPrefix + scopeIdentifier
        let readiness = HistoricalValuationReadinessCoordinator.shared

        let mainContext = modelContainer.mainContext
        let accounts: [Account]
        do {
            accounts = try mainContext.fetch(FetchDescriptor<Account>())
        } catch {
            readiness.fail(
                scopeID: scopeIdentifier,
                operation: .backfill,
                reasonCode: "backfill_account_fetch_failed"
            )
            return 0
        }
        guard !accounts.isEmpty else {
            // Счетов ядра ещё нет (старый мир до Legacy-конвертации/новый пользователь без счетов) —
            // отмечаем выполненным: как только появится первый счёт, ему всё равно не нужен «глубокий»
            // бэкфилл (создан только что), инкрементальный путь справится сам.
            readiness.complete(scopeID: scopeIdentifier, operation: .backfill)
            defaults.set(true, forKey: flagKey)
            return 0
        }

        let rebuilder = AccountSnapshotRebuilder(modelContainer: modelContainer)
        let now = nowProvider()
        var failures = 0
        for account in accounts {
            do {
                // Именно `rebuildAll`, а не инкрементальный `rebuild(upTo:)`: у существующего
                // пользователя кэш уже заполнен старыми значениями, и инкремент вышел бы рано,
                // оставив завышенные балансы вкладов в снапшотах (а через них — в бэкапе).
                try await rebuilder.rebuildAll(accountID: account.persistentModelID, upTo: now)
            } catch {
                failures += 1
                AppLogger.log(.error, category: "AccountsCore", "Snapshot backfill: счёт \(account.id) — \(error.localizedDescription)")
            }
        }

        if failures == 0 {
            // Terminal success is durable. Partial work is deliberately retried on the next launch;
            // otherwise an in-memory failure would disappear while the old boolean falsely claims
            // historical readiness.
            readiness.complete(scopeID: scopeIdentifier, operation: .backfill)
            defaults.set(true, forKey: flagKey)
        } else {
            readiness.fail(
                scopeID: scopeIdentifier,
                operation: .backfill,
                reasonCode: "backfill_partial_failure"
            )
        }
        AppLogger.log(.info, category: "AccountsCore", "Snapshot backfill [\(scopeIdentifier)] завершён: \(accounts.count) счетов, \(failures) ошибок")
        return accounts.count
    }
}
