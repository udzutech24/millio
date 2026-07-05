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
    private static let flagKeyPrefix = "migration.accountSnapshotBackfill.v1."

    private let modelContainer: ModelContainer
    private let defaults: UserDefaults
    private let nowProvider: () -> Date

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
        let flagKey = Self.flagKeyPrefix + scopeIdentifier
        guard !defaults.bool(forKey: flagKey) else { return 0 }

        let mainContext = modelContainer.mainContext
        guard let accounts = try? mainContext.fetch(FetchDescriptor<Account>()), !accounts.isEmpty else {
            // Счетов ядра ещё нет (старый мир до Legacy-конвертации/новый пользователь без счетов) —
            // отмечаем выполненным: как только появится первый счёт, ему всё равно не нужен «глубокий»
            // бэкфилл (создан только что), инкрементальный путь справится сам.
            defaults.set(true, forKey: flagKey)
            return 0
        }

        let rebuilder = AccountSnapshotRebuilder(modelContainer: modelContainer)
        let now = nowProvider()
        var failures = 0
        for account in accounts {
            do {
                try await rebuilder.rebuild(accountID: account.persistentModelID, upTo: now)
            } catch {
                failures += 1
                AppLogger.log(.error, category: "AccountsCore", "Snapshot backfill: счёт \(account.id) — \(error.localizedDescription)")
            }
        }

        // Флаг ставим даже при частичных ошибках — единичный сбой счёта не должен гонять
        // полный бэкфилл ВСЕХ счетов на каждом следующем холодном старте. Недостроенная история
        // такого счёта всё равно достраивается лениво через AccountsTotalsService при обращении.
        defaults.set(true, forKey: flagKey)
        AppLogger.log(.info, category: "AccountsCore", "Snapshot backfill [\(scopeIdentifier)] завершён: \(accounts.count) счетов, \(failures) ошибок")
        return accounts.count
    }
}
