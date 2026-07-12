import Foundation
import SwiftData
import Testing
@testable import millio

/// Self-heal легаси→core миграции после замены стора (restore до-AccountsCore-бэкапа / recovery-ребилд).
/// Регрессия: флаг `migration.legacyAccountsPurge.v1.<scope>` и реестр конверсий живут в UserDefaults,
/// а данные — в SwiftData; замена стора без ядра оставляла оба гейта «стоящими» → миграция не
/// перезапускалась и счета были невидимы навсегда (progress/2026-07-11-migration-flag-restore-bug.md,
/// plans/2026-07-12__legacy-migration-self-heal.md).
@Suite("LegacyAccountsMigrator self-heal (restore/recovery)")
@MainActor
struct LegacyMigrationSelfHealTests {

    private struct Stack {
        let ctx: ModelContext
        let container: ModelContainer
        let registry: LegacyConversionRegistry
        let migrator: LegacyAccountsMigrator
        let flagDefaults: UserDefaults
    }

    /// Ключ флага короткого замыкания — зеркалит `LegacyAccountsMigrator.flagKeyPrefix` (private static),
    /// чтобы тест мог сымитировать «флаг пережил замену стора».
    private func flagKey(_ scope: String) -> String { "migration.legacyAccountsPurge.v1." + scope }

    private func makeStack() throws -> Stack {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "heal-reg-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "heal-flag-\(UUID().uuidString)")!
        let migrator = LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults)
        return Stack(ctx: ctx, container: container, registry: registry, migrator: migrator, flagDefaults: flagDefaults)
    }

    @discardableResult
    private func seedCard(_ ctx: ModelContext, name: String = "ОГ", balance: Double = 150_000) -> Card {
        let card = Card(name: name, cardNumber: "1234", cardType: .debit, balance: balance)
        ctx.insert(card)
        return card
    }

    private func coreCount(_ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<Account>())
    }

    // MARK: - AC1: стор заменён без ядра (флаг стоит + реестр stale) → self-heal пересобирает ядро

    @Test("Core пуст + легаси есть + флаг стоит + реестр stale → миграция всё равно запускается")
    func selfHeal_rebuildsCoreDespiteStaleFlagAndRegistry() throws {
        let s = try makeStack()
        let scope = "heal-scope"

        // Состояние после restore до-AccountsCore-бэкапа: легаси-скелет вернулся, ядро пусто…
        let card = seedCard(s.ctx)
        try s.ctx.save()
        #expect(try coreCount(s.ctx) == 0)

        // …а флаг миграции и запись реестра «пережили» замену стора (указывают на несуществующий core).
        s.flagDefaults.set(true, forKey: flagKey(scope))
        s.registry.record(legacyUniqueID: card.cardUniqueID, coreAccountID: UUID())
        #expect(s.registry.isConverted(legacyUniqueID: card.cardUniqueID))

        let summary = s.migrator.migrateIfNeeded(scopeIdentifier: scope)

        // Coarse-detection перебивает и флаг, и stale-реестр → счёт пересоздан в ядре.
        #expect(summary.migrated == 1)
        #expect(summary.failures == 0)
        #expect(try coreCount(s.ctx) == 1)
        #expect(card.archivedAt != nil)

        // Реестр теперь указывает на РЕАЛЬНО существующий core-двойник (а не на осиротевший UUID).
        let coreID = try #require(s.registry.coreAccountID(forLegacyUniqueID: card.cardUniqueID))
        let twin = try s.ctx.fetch(FetchDescriptor<Account>(predicate: #Predicate<Account> { $0.id == coreID }))
        #expect(twin.count == 1)
    }

    // MARK: - AC2: ядро живое → coarse-detection НЕ срабатывает, флаг-short-circuit сохранён

    @Test("Ядро живое + легаси-остаток + флаг стоит → короткое замыкание (детект не перебивает)")
    func normalState_detectionDoesNotFire_flagShortCircuits() throws {
        let s = try makeStack()
        let scope = "normal-scope"

        // Первый прогон мигрирует карту (ядро становится непустым, флаг выставляется).
        seedCard(s.ctx, name: "Первая")
        try s.ctx.save()
        let first = s.migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(first.migrated == 1)
        #expect(try coreCount(s.ctx) == 1)

        // Появляется новая активная легаси (напр. осиротевший скелет), но ЯДРО НЕПУСТО.
        // Детект гейтится на `Account count == 0` → не срабатывает; флаг стоит → полное короткое
        // замыкание, новая легаси НЕ мигрируется этим прогоном (штатное поведение, не self-heal).
        seedCard(s.ctx, name: "Вторая")
        try s.ctx.save()
        let second = s.migrator.migrateIfNeeded(scopeIdentifier: scope)

        #expect(second == LegacyAccountsMigrator.Summary())
        #expect(try coreCount(s.ctx) == 1)
    }

    // MARK: - AC3: повторный self-heal идемпотентен (без дублей)

    @Test("Повторный прогон после self-heal → без дублей ядра")
    func repeatedRunAfterSelfHeal_isIdempotent() throws {
        let s = try makeStack()
        let scope = "idem-scope"

        let card = seedCard(s.ctx)
        try s.ctx.save()
        s.flagDefaults.set(true, forKey: flagKey(scope))
        s.registry.record(legacyUniqueID: card.cardUniqueID, coreAccountID: UUID())

        let healed = s.migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(healed.migrated == 1)
        #expect(try coreCount(s.ctx) == 1)

        // Второй прогон: ядро уже непусто (детект не срабатывает), флаг переставлен после успешного
        // heal → короткое замыкание. Ни нового двойника, ни повторной миграции скрытой легаси.
        let again = s.migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(again == LegacyAccountsMigrator.Summary())
        #expect(try coreCount(s.ctx) == 1)

        // Даже прямой migrateAll (без флаг-гейта) — no-op: легаси скрыта archivedAt.
        let raw = s.migrator.migrateAll()
        #expect(raw.migrated == 0)
        #expect(try coreCount(s.ctx) == 1)
    }

    @Test("Пустой стор (свежая установка) → self-heal не срабатывает, обычный флаг-путь")
    func emptyStore_doesNotTriggerSelfHeal() throws {
        let s = try makeStack()
        let scope = "empty-scope"

        // Ни легаси, ни ядра → детект «стор заменён без ядра» ложен (нет легаси-остатка).
        let summary = s.migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(summary == LegacyAccountsMigrator.Summary())
        #expect(try coreCount(s.ctx) == 0)
        // Флаг выставлен (штатный короткий путь), второй прогон — короткое замыкание.
        #expect(s.flagDefaults.bool(forKey: flagKey(scope)))
    }

    // MARK: - AC5 (адверсариально): легаси-only стор считается «непустым» recovery-логикой

    /// Проверяет соседний путь `presentRestoreFlowIfNeeded`/`exportedModelCount` (millioApp.swift:979):
    /// подсчёт «пустой ли стор» включает легаси-таблицы, поэтому легаси-only стор — «непустой»
    /// (`localDataCount > 0`). Значит restore-флоу его НЕ трогает как «пустой», а лечит именно
    /// self-heal-миграция (Часть A/B). Тест фиксирует это, чтобы будущая правка счётчика не сломала
    /// разграничение «recovery vs self-heal».
    @Test("Легаси-only стор экспортирует > 0 моделей → recovery видит его непустым (self-heal, не restore)")
    func legacyOnlyStore_countsAsNonEmpty() throws {
        let s = try makeStack()
        seedCard(s.ctx)
        _ = seedCard(s.ctx, name: "Вторая")
        try s.ctx.save()
        #expect(try coreCount(s.ctx) == 0)

        let payload = try DataRepository.exportAllData(from: s.ctx)
        let json = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])
        let models = try #require(json["models"] as? [[String: Any]])
        #expect(models.count > 0)
    }
}
