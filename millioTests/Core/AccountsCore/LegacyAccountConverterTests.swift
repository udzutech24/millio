import Foundation
import SwiftData
import Testing
@testable import millio

/// Фиксированный курс для инвариантных тестов конвертации (Track C).
@MainActor
final class FixedRateService: CurrencyRateServiceProtocol {
    var usdToRub: Double = 90

    func getRate(from: String, to: String) async -> Double? {
        let f = from.uppercased(); let t = to.uppercased()
        if f == t { return 1 }
        if f == "USD" && t == "RUB" { return usdToRub }
        if f == "RUB" && t == "USD" { return 1 / usdToRub }
        return nil
    }

    func getHistoricalRate(on date: Date, from: String, to: String) async -> Double? {
        await getRate(from: from, to: to)
    }

    func convert(amount: Double, from: String, to: String) async -> Double? {
        guard let rate = await getRate(from: from, to: to) else { return nil }
        return amount * rate
    }

    func forceRefreshRates() async {}
}

private struct HideLegacyBoom: Error {}

@Suite("LegacyAccountConverter (Track C)")
@MainActor
struct LegacyAccountConverterTests {

    private func makeStack() throws -> (ctx: ModelContext, totals: AccountsTotalsService, converter: LegacyAccountConverter, rate: FixedRateService) {
        let container = try AppMigrationPlan.makeInMemoryContainer()
        let ctx = container.mainContext
        let rate = FixedRateService()
        let totals = AccountsTotalsService(
            modelContext: ctx,
            rebuilder: AccountSnapshotRebuilder(modelContainer: container),
            rateService: rate
        )
        let registry = LegacyConversionRegistry(defaults: UserDefaults(suiteName: "conv-test-\(UUID().uuidString)")!)
        let converter = LegacyAccountConverter(modelContext: ctx, registry: registry)
        return (ctx, totals, converter, rate)
    }

    private func input(
        id: String = "legacy-1",
        currency: String = "RUB",
        kind: AccountKind = .debitCard,
        opening: Decimal
    ) -> LegacyAccountConverter.Input {
        LegacyAccountConverter.Input(
            legacyUniqueID: id, name: "ОГ", currency: currency, kind: kind,
            openingBalance: opening, group: nil, cardMeta: nil, loanMeta: nil, manualAssetMeta: nil
        )
    }

    // MARK: - Тест 1: конвертация — тотал не меняется, легаси скрыт, двойник с балансом легаси

    @Test
    func convertAbsorbsLegacyBalance_totalUnchanged() async throws {
        let s = try makeStack()

        let before = await s.totals.totalAt(Date(), in: "RUB")
        #expect(before == 0) // ядро пусто; легаси (150000) сейчас вне ядра

        var hidden = false
        let twin = try s.converter.convert(input(opening: 150_000)) { hidden = true }

        #expect(hidden) // легаси скрыт В ТОМ ЖЕ акте
        #expect(s.converter.isConverted(legacyUniqueID: "legacy-1"))
        #expect(twin.currency == "RUB")

        // Ядро теперь вносит ровно то, что вносил легаси (150000) → системный тотал неизменен.
        let after = await s.totals.totalAt(Date(), in: "RUB")
        #expect(after == 150_000)

        // Двойник существует ровно один.
        let count = try s.ctx.fetchCount(FetchDescriptor<Account>())
        #expect(count == 1)
    }

    // MARK: - Тест 2: un-convert — полный возврат, тотал неизменен, двойник удалён

    @Test
    func unconvertRemovesTwin_totalBackToBaseline() async throws {
        let s = try makeStack()
        _ = try s.converter.convert(input(opening: 150_000)) {}
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 150_000)

        var restored = false
        try s.converter.unconvert(legacyUniqueID: "legacy-1") { restored = true }

        #expect(restored)
        #expect(!s.converter.isConverted(legacyUniqueID: "legacy-1"))
        // Двойник удалён; легаси вернулся вне ядра → ядро снова вносит 0 (системный тотал неизменен).
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 0)
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 0)
    }

    // MARK: - Тест 3: повторная конвертация после отката работает

    @Test
    func reconvertAfterUnconvertWorks() async throws {
        let s = try makeStack()
        _ = try s.converter.convert(input(opening: 150_000)) {}
        try s.converter.unconvert(legacyUniqueID: "legacy-1") {}
        _ = try s.converter.convert(input(opening: 150_000)) {}

        #expect(s.converter.isConverted(legacyUniqueID: "legacy-1"))
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 150_000)
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 1)
    }

    // MARK: - Тест 4: валюта != primary — тотал в primary неизменен

    @Test
    func convertNonPrimaryCurrency_primaryTotalUnchanged() async throws {
        let s = try makeStack()
        s.rate.usdToRub = 90

        // Легаси USD-счёт на 100$ вносил 100×90 = 9000 ₽ в primary-тотал.
        let twin = try s.converter.convert(input(id: "usd-1", currency: "USD", opening: 100)) {}

        #expect(twin.currency == "USD")
        // Двойник вносит ровно 9000 ₽ — primary-тотал неизменен.
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 9000)
    }

    // MARK: - Маппинг знака движка: loan даёт отрицательный баланс, manualAsset замораживает

    @Test
    func loanKindProducesNegativeBalance() async throws {
        let s = try makeStack()
        // Кредит: getAccountAmount вносит −remainingAmount; opening = магнитуда, движок C инвертирует.
        _ = try s.converter.convert(input(id: "credit-1", kind: .loan, opening: 500_000)) {}
        #expect(await s.totals.totalAt(Date(), in: "RUB") == -500_000)
    }

    @Test
    func manualAssetKindFreezesValue() async throws {
        let s = try makeStack()
        _ = try s.converter.convert(input(id: "inv-1", kind: .manualAsset, opening: 20_000_000)) {}
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 20_000_000)
    }

    // MARK: - Атомарность: сбой скрытия легаси откатывает двойник (риск №8)

    @Test
    func hideLegacyFailureRollsBackTwin() async throws {
        let s = try makeStack()

        do {
            _ = try s.converter.convert(input(opening: 150_000)) { throw HideLegacyBoom() }
            Issue.record("convert должен был бросить ошибку скрытия легаси")
        } catch is HideLegacyBoom {
            // ожидаемо
        }

        // Компенсация: ни двойника, ни записи реестра — иначе двойной счёт в тотале.
        #expect(!s.converter.isConverted(legacyUniqueID: "legacy-1"))
        #expect(try s.ctx.fetchCount(FetchDescriptor<Account>()) == 0)
        #expect(await s.totals.totalAt(Date(), in: "RUB") == 0)
    }

    // MARK: - Реестр: запись/чтение/удаление

    @Test
    func registryRecordsAndClears() {
        let defaults = UserDefaults(suiteName: "reg-test-\(UUID().uuidString)")!
        let registry = LegacyConversionRegistry(defaults: defaults)
        let id = UUID()

        #expect(!registry.isConverted(legacyUniqueID: "x"))
        registry.record(legacyUniqueID: "x", coreAccountID: id)
        #expect(registry.isConverted(legacyUniqueID: "x"))
        #expect(registry.coreAccountID(forLegacyUniqueID: "x") == id)
        registry.remove(legacyUniqueID: "x")
        #expect(!registry.isConverted(legacyUniqueID: "x"))
    }
}
