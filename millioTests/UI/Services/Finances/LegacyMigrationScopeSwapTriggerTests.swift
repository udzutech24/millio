import Foundation
import SwiftData
import Testing
@testable import millio

/// Триггер-гэп легаси→core миграции при АСИНХРОННОМ свопе scope (cold-start guest → login user).
///
/// Регрессия (доказана логами устройства владельца): `runLegacyAccountsMigrationIfNeeded` висел только
/// на cold-start-замыкании `onScopeResolved` (millioApp.swift:262), исполнявшемся на scope, что
/// резолвится синхронно на холодном старте (в реальном кейсе — `guest`, без легаси). Онлайн-переключение
/// на `user` идёт ПОЗЖЕ, отдельным async-путём `onSessionChanged` → `synchronizeDataScope(onScopeResolved: nil)`
/// → `rebindDataScope` (своп `activeModelContainer`/`diContainer`) — но миграцию НЕ переигрывал. Итог:
/// user-стор со своими легаси-записями (`Card`/`FinanceAccount`/`Investment`) и пустым ядром
/// (`core.Account = 0`) оставался немигрированным навсегда, счета невидимы
/// (progress/2026-07-11-migration-flag-restore-bug.md, plans/2026-07-12__legacy-migration-self-heal.md).
///
/// Фикс: вызов миграции добавлен в `rebindDataScope` СТРОГО ПОСЛЕ свопа `diContainer` — единый
/// choke-point активации контейнера, поэтому КАЖДЫЙ scope, чей контейнер становится активным, мигрируется.
/// Эти тесты моделируют миграцию на ДВУХ scope (guest→user) с общими `registry`/флаг-дефолтами — как в
/// проде (`LegacyConversionRegistry.shared` + `UserDefaults.standard`, per-scope ключ флага). Сам вызов из
/// `rebindDataScope` (приватный метод SwiftUI-`App`) проверяется сборкой + device-тестом.
@Suite("Легаси-миграция: триггер при async scope-swap (guest→user)")
@MainActor
struct LegacyMigrationScopeSwapTriggerTests {

    private func makeMigrator(
        _ ctx: ModelContext,
        registry: LegacyConversionRegistry,
        flagDefaults: UserDefaults
    ) -> LegacyAccountsMigrator {
        LegacyAccountsMigrator(modelContext: ctx, registry: registry, defaults: flagDefaults)
    }

    @discardableResult
    private func seedCard(_ ctx: ModelContext, name: String = "ОГ", balance: Double = 150_000) -> Card {
        let card = Card(name: name, cardNumber: "1234", cardType: .debit, balance: balance)
        ctx.insert(card)
        return card
    }

    @discardableResult
    private func seedInvestment(_ ctx: ModelContext, name: String = "Квартира", amount: Double = 20_000_000) -> Investment {
        let inv = Investment(name: name, investmentType: .positive, category: .house, amount: amount)
        ctx.insert(inv)
        return inv
    }

    /// Junction-строка группировки (`FinanceAccount`) — как в проде заполняет карту групп мигратора
    /// и присутствует в user-сторе владельца (`legacy.FinanceAccount = 63`).
    private func seedGroupLink(_ ctx: ModelContext, card: Card, groupName: String) {
        let group = FinanceGroup(name: groupName)
        ctx.insert(group)
        let link = FinanceAccount(accountType: .card, accountID: card.cardUniqueID)
        link.group = group
        ctx.insert(link)
    }

    private func coreCount(_ ctx: ModelContext) throws -> Int {
        try ctx.fetchCount(FetchDescriptor<Account>())
    }

    private func flagKey(_ scope: String) -> String { "migration.legacyAccountsPurge.v1." + scope }

    // MARK: - Тест 1: cold-start guest (без легаси) → swap на user (со своими легаси) заполняет ядро user

    @Test("Cold-start мигрирует guest (пусто), затем swap на user со своими легаси → ядро user заполнено")
    func coldStartGuestThenUserSwap_migratesUserCoreAfterSwap() throws {
        // Общие для обоих scope — как в проде (registry.shared + UserDefaults.standard, per-scope ключ).
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "swap-reg-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "swap-flag-\(UUID().uuidString)")!

        // 1) Cold-start: активен guest-стор без легаси. Миграция guest — вхолостую (ядро остаётся пустым).
        let guest = try AppMigrationPlan.makeInMemoryContainer()
        let guestMigrator = makeMigrator(guest.mainContext, registry: registry, flagDefaults: flagDefaults)
        let guestSummary = guestMigrator.migrateIfNeeded(scopeIdentifier: "guest")
        #expect(guestSummary == LegacyAccountsMigrator.Summary())
        #expect(try coreCount(guest.mainContext) == 0)

        // 2) Login → async swap на user-стор со СВОИМИ легаси (Card + FinanceAccount + Investment)
        //    и пустым ядром — ровно состояние из лога устройства (core.Account = 0, legacy непусто).
        let user = try AppMigrationPlan.makeInMemoryContainer()
        let card = seedCard(user.mainContext)
        seedGroupLink(user.mainContext, card: card, groupName: "Инвесткошелёк")
        let inv = seedInvestment(user.mainContext)
        try user.mainContext.save()
        #expect(try coreCount(user.mainContext) == 0)

        // rebindDataScope после свопа diContainer теперь вызывает миграцию для НОВОГО scope — моделируем.
        let userMigrator = makeMigrator(user.mainContext, registry: registry, flagDefaults: flagDefaults)
        let userSummary = userMigrator.migrateIfNeeded(scopeIdentifier: "user")

        // Ядро user заполнено: оба легаси-счёта мигрированы, легаси скрыты, группа перенесена на двойника.
        #expect(userSummary.migrated == 2)
        #expect(userSummary.failures == 0)
        #expect(try coreCount(user.mainContext) == 2)
        #expect(card.archivedAt != nil)
        #expect(inv.archivedAt != nil)
        let twins = try user.mainContext.fetch(FetchDescriptor<Account>())
        #expect(twins.contains { $0.group?.name == "Инвесткошелёк" })
    }

    // MARK: - Тест 2: повторный триггер на том же scope (двойной вызов на cold-start) → дешёвый no-op

    @Test("Повторный триггер на уже мигрированном scope → флаг-short-circuit, без лишней работы (только fetchCount)")
    func redundantSecondTriggerOnSameScope_isCheapNoOp() throws {
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "noop-reg-\(UUID().uuidString)")!)
        let flagDefaults = UserDefaults(suiteName: "noop-flag-\(UUID().uuidString)")!
        let scope = "user"

        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        seedCard(ctx)
        seedInvestment(ctx)
        try ctx.save()

        // Первый триггер (из rebindDataScope после свопа) — реально мигрирует и ставит per-scope флаг.
        let migrator = makeMigrator(ctx, registry: registry, flagDefaults: flagDefaults)
        let first = migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(first.migrated == 2)
        #expect(try coreCount(ctx) == 2)
        #expect(flagDefaults.bool(forKey: flagKey(scope)))  // флаг стоит → второй вызов уйдёт в short-circuit

        // Зонд «прошёл ли скан migrateAll»: между двумя вызовами появляется свежая АКТИВНАЯ легаси.
        // Если бы избыточный второй триггер сканировал стор, он бы её мигрировал (ядро → 3). На реальном
        // cold-start новой легаси между вызовами нет — зонд лишь ловит факт скана, а не моделирует тайминг.
        seedCard(ctx, name: "После первого прогона")
        try ctx.save()

        // Второй триггер в том же процессе (cold-start onScopeResolved после rebindDataScope) — дешёвый
        // no-op: storeReplacedWithoutCore = один fetchCount(Account) (ядро непусто → false), затем флаг → выход.
        let second = migrator.migrateIfNeeded(scopeIdentifier: scope)
        #expect(second == LegacyAccountsMigrator.Summary())
        // Зонд НЕ мигрирован → migrateAll не выполнялся (флаг-short-circuit): лишней работы нет.
        #expect(try coreCount(ctx) == 2)
    }
}
