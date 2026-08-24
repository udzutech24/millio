//
//  CurrencyRateSnapshotPersistenceTests.swift
//  millioTests
//
//  Регрессия на баг с устройства (2026-08-24): «как будто нет архива после закрытия прилы, потому
//  постоянно грузится, и там где счета когда грузится дёргается экран, тк появляется кругляшок
//  загрузки курсов». Снимок курсов обязан переживать перезапуск и быть доступным СИНХРОННО в init,
//  а ревизия снимка обязана зависеть от значений курсов, а не от времени загрузки.
//

import Foundation
import Testing
@testable import millio

@Suite("Курсы: персистентность снимка между запусками", .serialized)
@MainActor
struct CurrencyRateSnapshotPersistenceTests {

    private func clearPersistedRates(_ source: RateSource) {
        let ud = UserDefaults.standard
        ud.removeObject(forKey: "rate_repo_rates_\(source.rawValue)")
        ud.removeObject(forKey: "rate_repo_updated_at_\(source.rawValue)")
        ud.removeObject(forKey: "rate_repo_fetched_at_\(source.rawValue)")
        CurrencyRateSnapshotRevisionStore.clear()
    }

    private func persistRates(_ rates: [String: Double], source: RateSource, fetchedAt: Double) {
        let ud = UserDefaults.standard
        ud.set(rates, forKey: "rate_repo_rates_\(source.rawValue)")
        ud.set(fetchedAt, forKey: "rate_repo_updated_at_\(source.rawValue)")
        ud.set(fetchedAt, forKey: "rate_repo_fetched_at_\(source.rawValue)")
    }

    // MARK: - Снимок переживает перезапуск

    @Test("Холодный старт: снимок читается с диска синхронно в init, без сети")
    func testSnapshotSurvivesRelaunch() async {
        clearPersistedRates(.millio)
        defer { clearPersistedRates(.millio) }

        let fetchedAt = Date().timeIntervalSince1970 - 600 // 10 минут назад — кэш ещё свежий
        persistRates(["USD": 1, "EUR": 0.9, "RUB": 80], source: .millio, fetchedAt: fetchedAt)

        // Новый экземпляр = холодный старт приложения.
        let repo = MockRateRepository()
        repo.shouldFail = true // сеть недоступна — снимок обязан прийти только с диска
        let service = CurrencyRateService(rateSource: .millio, rateRepository: repo)

        let snapshot = service.currentRateSnapshot()
        #expect(snapshot != nil)
        #expect(snapshot?.rates["RUB"] == 80)
        #expect(snapshot?.fetchedAt == fetchedAt)
        // Синхронный доступ к курсу — до любого await, то есть уже на первом кадре UI.
        #expect(service.getCachedRate(from: "USD", to: "RUB") == 80)
        #expect(repo.callCount == 0)
    }

    @Test("Пустой диск: снимка нет — это единственный случай, когда показывать нечего")
    func testNoSnapshotOnFirstEverLaunch() {
        clearPersistedRates(.millio)
        defer { clearPersistedRates(.millio) }

        let service = CurrencyRateService(rateSource: .millio, rateRepository: MockRateRepository())
        #expect(service.currentRateSnapshot() == nil)
    }

    @Test("После restore снимок курсов не теряется: новый сервис поднимает его с диска")
    func testSnapshotAvailableAfterRestoreRelaunch() async {
        clearPersistedRates(.millio)
        defer { clearPersistedRates(.millio) }

        // Сессия до restore: курсы получены из сети и сохранены репозиторием.
        let repo = MockRateRepository()
        repo.rates = ["USD": 1, "EUR": 0.9, "RUB": 95]
        let before = CurrencyRateService(rateSource: .millio, rateRepository: repo)
        await before.forceRefreshRates()
        persistRates(repo.rates, source: .millio, fetchedAt: Date().timeIntervalSince1970)

        // Restore заменяет SwiftData-стор, но не трогает кэш курсов — после перезапуска он на месте.
        let after = CurrencyRateService(rateSource: .millio, rateRepository: MockRateRepository())
        #expect(after.currentRateSnapshot()?.rates["RUB"] == 95)
    }

    // MARK: - Ревизия по значениям, а не по времени загрузки

    @Test("Ревизия не меняется, если фоновое обновление принесло те же курсы")
    func testRevisionStableForIdenticalRates() {
        let rates = ["USD": 1.0, "EUR": 0.9, "RUB": 80.0]
        let first = RateSnapshot(source: .millio, rates: rates, updatedAt: 1_700_000_000, fetchedAt: 1_700_000_000)
        let secondFetchSameValues = RateSnapshot(source: .millio, rates: rates, updatedAt: 1_700_050_000, fetchedAt: 1_700_099_999)

        #expect(
            CurrencyRateSnapshotRevisionStore.revision(for: first)
                == CurrencyRateSnapshotRevisionStore.revision(for: secondFetchSameValues)
        )
    }

    @Test("Ревизия меняется при изменении курса и при смене источника")
    func testRevisionChangesForDifferentRatesOrSource() {
        let base = RateSnapshot(source: .millio, rates: ["USD": 1, "RUB": 80], updatedAt: 1, fetchedAt: 1)
        let changedRate = RateSnapshot(source: .millio, rates: ["USD": 1, "RUB": 81], updatedAt: 1, fetchedAt: 1)
        let changedSource = RateSnapshot(source: .erapi, rates: ["USD": 1, "RUB": 80], updatedAt: 1, fetchedAt: 1)

        #expect(CurrencyRateSnapshotRevisionStore.revision(for: base) != CurrencyRateSnapshotRevisionStore.revision(for: changedRate))
        #expect(CurrencyRateSnapshotRevisionStore.revision(for: base) != CurrencyRateSnapshotRevisionStore.revision(for: changedSource))
    }

    @Test("Ревизия детерминирована — иначе не пережила бы перезапуск процесса")
    func testRevisionIsDeterministic() {
        let snapshot = RateSnapshot(source: .millio, rates: ["USD": 1, "RUB": 80], updatedAt: 5, fetchedAt: 7)
        let stored = CurrencyRateSnapshotRevisionStore.save(snapshot)
        defer { CurrencyRateSnapshotRevisionStore.clear() }

        #expect(CurrencyRateSnapshotRevisionStore.current == stored)
        #expect(CurrencyRateSnapshotRevisionStore.revision(for: snapshot) == stored)
    }

    // MARK: - Фоновое обновление с теми же значениями не будит UI

    @Test("Повторный fetch с теми же курсами не публикует currencyRateSnapshotDidChange")
    func testIdenticalBackgroundRefreshDoesNotNotify() async {
        clearPersistedRates(.millio)
        defer { clearPersistedRates(.millio) }

        let repo = MockRateRepository()
        repo.rates = ["USD": 1, "EUR": 0.9, "RUB": 80]
        let service = CurrencyRateService(rateSource: .millio, rateRepository: repo)

        var notifications = 0
        // Фильтруем по своему сервису: параллельные @Suite тоже шлют это уведомление.
        let observer = NotificationCenter.default.addObserver(
            forName: .currencyRateSnapshotDidChange,
            object: service,
            queue: .main
        ) { _ in notifications += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        await service.forceRefreshRates()
        let afterFirst = notifications

        // Мок отдаёт новый fetchedAt, но те же значения — UI перестраивать не из-за чего.
        await service.forceRefreshRates()
        await service.forceRefreshRates()

        #expect(afterFirst == 1)
        #expect(notifications == afterFirst)

        // Реально изменившийся курс обязан разбудить подписчиков.
        repo.rates = ["USD": 1, "EUR": 0.9, "RUB": 91]
        await service.forceRefreshRates()
        #expect(notifications == afterFirst + 1)
    }
}
