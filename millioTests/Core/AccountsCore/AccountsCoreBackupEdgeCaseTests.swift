import Foundation
import SwiftData
import Testing
@testable import millio

/// Закрепляющие тесты на асимметричное, но НАМЕРЕННОЕ поведение импортёров ядра счетов
/// (адверсарный аудит коммита 0cab037, ModelTypeRegistry-блокер): dangling FK, TZ-риск Т5,
/// повреждённые Decimal-строки. Продакшен-код не меняется — только фиксация текущего поведения.
@Suite(.serialized)
@MainActor
struct AccountsCoreBackupEdgeCaseTests {

    private func withRegistry(_ body: () throws -> Void) throws {
        let state = ModelTypeRegistry.shared.captureState()
        FinanceFeatureRegistration.register()
        CardFeatureRegistration.register()
        AccountsCoreFeatureRegistration.register()
        do { try body() } catch { ModelTypeRegistry.shared.restoreState(state); throw error }
        ModelTypeRegistry.shared.restoreState(state)
    }

    /// Подменяет значение по ключу во ВСЕХ моделях данного `_type` внутри backup-JSON — имитация
    /// повреждённого/усечённого бэкапа (частичный экспорт, устаревший снапшот со ссылкой на уже
    /// удалённую сущность и т.п.).
    private func tamperedBackup(_ data: Data, type: String, key: String, value: Any) throws -> Data {
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var models = json["models"] as! [[String: Any]]
        for index in models.indices where models[index]["_type"] as? String == type {
            models[index][key] = value
        }
        json["models"] = models
        return try JSONSerialization.data(withJSONObject: json)
    }

    // MARK: - Dangling FK

    @Test("Dangling FK: несуществующие groupID/accountID резолвятся в nil без краша и без потери остальных данных")
    func testDanglingForeignKeysResolveToNilWithoutCrash() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let account = Account(name: "Без группы", kind: .cash)
            context.insert(account)
            let event = AccountEvent(account: account, date: Date(timeIntervalSince1970: 1_700_000_000),
                                      type: .openingBalance, amount: 500)
            context.insert(event)
            try context.save()

            var backupData = try DataRepository.exportAllData(from: context)
            backupData = try tamperedBackup(backupData, type: "Account", key: "groupID", value: UUID().uuidString)
            backupData = try tamperedBackup(backupData, type: "AccountEvent", key: "accountID", value: UUID().uuidString)

            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            try repository.importAllData(backupData) // не должно бросить исключение

            let restoredAccounts = try context.fetch(FetchDescriptor<Account>())
            #expect(restoredAccounts.count == 1, "Сама сущность должна импортироваться, несмотря на dangling FK")
            #expect(restoredAccounts.first?.group == nil, "Несуществующая группа резолвится в nil, а не в краш")

            let restoredEvents = try context.fetch(FetchDescriptor<AccountEvent>())
            #expect(restoredEvents.count == 1)
            #expect(restoredEvents.first?.account == nil, "Несуществующий счёт резолвится в nil, а не в краш")
        }
    }

    // MARK: - Буквальный TZ-тест (риск Т5)

    @Test("dayKey переживает смену системной таймзоны между экспортом и импортом (риск Т5)")
    func testDayKeySurvivesTimeZoneChangeBetweenExportAndImport() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext
            let account = Account(name: "Счёт", kind: .cash)
            context.insert(account)

            // Инстант, попадающий в РАЗНЫЕ календарные дни в Токио и Нью-Йорке — проверено эмпирически
            // (Asia/Tokyo → 2025-06-16, America/New_York → 2025-06-15) тем же кодом, что и
            // `AccountEvent.makeDayKey` (Calendar(identifier: .gregorian) без явного timeZone —
            // подхватывает `NSTimeZone.default`).
            let date = Date(timeIntervalSince1970: 1_750_000_000)
            let originalDefaultTZ = NSTimeZone.default

            NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
            let event = AccountEvent(account: account, date: date, type: .openingBalance, amount: 100)
            NSTimeZone.default = originalDefaultTZ
            context.insert(event)
            try context.save()

            let tokyoDayKey = event.dayKey
            #expect(tokyoDayKey == "2025-06-16") // страховка от «немого» совпадения TZ окружения

            let backupData = try DataRepository.exportAllData(from: context)
            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()

            // Критическая секция максимально узкая + восстановление в defer (даже при throw) —
            // мутация NSTimeZone.default глобальна для процесса, минимизируем риск влияния на
            // параллельно выполняющиеся тесты (тот же класс риска, что LanguageManager.shared).
            NSTimeZone.default = TimeZone(identifier: "America/New_York")!
            defer { NSTimeZone.default = originalDefaultTZ }
            try repository.importAllData(backupData)
            NSTimeZone.default = originalDefaultTZ

            let restoredEvents = try context.fetch(FetchDescriptor<AccountEvent>())
            let restoredEvent = try #require(restoredEvents.first)
            #expect(restoredEvent.dayKey == tokyoDayKey,
                     "dayKey должен остаться днём экспорта (Токио), а не пересчитаться под текущую TZ импорта (Нью-Йорк)")
            #expect(restoredEvent.dayKey != "2025-06-15",
                     "Если бы импорт пересчитывал dayKey из date под New York TZ — получили бы другой день")
        }
    }

    // MARK: - Повреждённые Decimal-строки — асимметрия optional-meta vs required-top-level

    @Test("Битая Decimal-строка в опциональном meta-поле — silent nil, остальная сущность и бэкап импортируются")
    func testCorruptedOptionalDecimalInMetaSilentlyDropsOnlyThatField() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let account = Account(name: "Карта", kind: .debitCard)
            account.cardMeta = CardMeta(bank: "Т-Банк", last4: "9999", creditLimit: 50_000,
                                         statementDay: nil, dueDay: nil, minPayment: nil,
                                         graceDays: nil, overdraftLimit: nil)
            context.insert(account)
            let otherAccount = Account(name: "Ещё счёт", kind: .cash)
            context.insert(otherAccount)
            try context.save()

            var backupData = try DataRepository.exportAllData(from: context)
            var json = try JSONSerialization.jsonObject(with: backupData) as! [String: Any]
            var models = json["models"] as! [[String: Any]]
            for index in models.indices {
                if models[index]["_type"] as? String == "Account",
                   var cardMeta = models[index]["cardMeta"] as? [String: Any] {
                    cardMeta["creditLimit"] = "not-a-decimal"
                    models[index]["cardMeta"] = cardMeta
                }
            }
            json["models"] = models
            backupData = try JSONSerialization.data(withJSONObject: json)

            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()
            try repository.importAllData(backupData) // CardMeta не failable — не должно бросить

            let restoredAccounts = try context.fetch(FetchDescriptor<Account>())
            #expect(restoredAccounts.count == 2, "Повреждение одного поля не должно обрушить остальной бэкап")

            let restoredCard = restoredAccounts.first { $0.kind == .debitCard }
            #expect(restoredCard?.cardMeta != nil, "CardMeta не failable — структура восстанавливается")
            #expect(restoredCard?.cardMeta?.bank == "Т-Банк", "Остальные поля meta не пострадали")
            #expect(restoredCard?.cardMeta?.creditLimit == nil, "Битое значение тихо становится nil, а не крашит импорт")
        }
    }

    @Test("Битая Decimal-строка в обязательном top-level поле — backupCorrupted на весь restore")
    func testCorruptedRequiredTopLevelDecimalThrowsBackupCorrupted() throws {
        try withRegistry {
            let container = try AppMigrationPlan.makeInMemoryContainer()
            let context = container.mainContext

            let account = Account(name: "Счёт", kind: .cash)
            context.insert(account)
            let snapshot = AccountDailySnapshot(account: account, dayKey: "2025-06-01", balance: 1_000)
            context.insert(snapshot)
            try context.save()

            let backupData = try tamperedBackup(
                try DataRepository.exportAllData(from: context),
                type: "AccountDailySnapshot", key: "balance", value: "not-a-decimal"
            )

            let repository = DataRepository(modelContext: context, modelContainer: container)
            try repository.clearAllData()

            #expect(throws: AppError.backupCorrupted) {
                try repository.importAllData(backupData)
            }
        }
    }
}
