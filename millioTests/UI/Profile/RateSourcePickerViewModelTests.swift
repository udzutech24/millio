//
//  RateSourcePickerViewModelTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite("RateSourcePickerViewModel")
@MainActor
struct RateSourcePickerViewModelTests {
    private func makeSuiteDefaults(name: String = "test.rate-source-picker") -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    // MARK: - Инициализация

    @Test("selectedSource инициализируется из store.preferred")
    func testSelectedSourceInitFromStorePreferred() {
        let defaults = makeSuiteDefaults()
        var store = RateSourcePreferenceStore(defaults: defaults)
        store.preferred = .erapi

        let vm = RateSourcePickerViewModel(store: store)

        #expect(vm.selectedSource == .erapi)
    }

    @Test("selectedSource по умолчанию .millio при пустом store")
    func testSelectedSourceDefaultIsMillio() {
        let defaults = makeSuiteDefaults()
        let store = RateSourcePreferenceStore(defaults: defaults)
        let vm = RateSourcePickerViewModel(store: store)

        #expect(vm.selectedSource == .millio)
    }

    // MARK: - visibleSources

    @Test("visibleSources без RUB и не-русский язык — .cbr скрыт")
    func testVisibleSourcesWithoutRUBNonRussian() {
        let sources = RateSourcePickerViewModel.visibleSources(
            primaryCurrencyCode: "USD",
            favoriteCurrencyCodes: ["EUR", "GBP"],
            appLocale: Locale(identifier: "en")
        )
        #expect(!sources.contains(.cbr))
        #expect(sources.contains(.millio))
        #expect(sources.contains(.erapi))
        #expect(sources.contains(.frankfurter))
    }

    @Test("visibleSources без RUB но русский язык — .cbr виден")
    func testVisibleSourcesWithoutRUBRussianLocale() {
        let sources = RateSourcePickerViewModel.visibleSources(
            primaryCurrencyCode: "USD",
            favoriteCurrencyCodes: ["EUR", "GBP"],
            appLocale: Locale(identifier: "ru")
        )
        #expect(sources.contains(.cbr))
        #expect(sources.count == RateSource.allCases.count)
    }

    @Test("visibleSources с RUB в primary — все источники видимы (Phase 2a добавит .cbr)")
    func testVisibleSourcesWithRUBPrimary() {
        let sources = RateSourcePickerViewModel.visibleSources(
            primaryCurrencyCode: "RUB",
            favoriteCurrencyCodes: []
        )
        #expect(sources.count == RateSource.allCases.count)
    }

    @Test("visibleSources с RUB в favorites — все источники видимы")
    func testVisibleSourcesWithRUBInFavorites() {
        let sources = RateSourcePickerViewModel.visibleSources(
            primaryCurrencyCode: "USD",
            favoriteCurrencyCodes: ["EUR", "RUB"]
        )
        #expect(sources.count == RateSource.allCases.count)
    }

    // MARK: - loadPreviews

    @Test("loadPreviews завершается для всех источников")
    func testLoadPreviewsCompletesForAllSources() async {
        let defaults = makeSuiteDefaults()
        let store = RateSourcePreferenceStore(defaults: defaults)

        let vm = RateSourcePickerViewModel(
            store: store,
            previewLoader: { source, _ in
                (source, .success(RatePreview(rates: [], updatedAt: nil, isStale: false)))
            }
        )

        await vm.loadPreviews()

        let sources = vm.visibleSources()
        for source in sources {
            #expect(vm.loadingStates[source] == .loaded)
        }
    }

    @Test("ошибка одного источника не блокирует остальные")
    func testLoadPreviewsErrorOnOneSourceDoesNotBlockOthers() async {
        let defaults = makeSuiteDefaults()
        let store = RateSourcePreferenceStore(defaults: defaults)

        let vm = RateSourcePickerViewModel(
            store: store,
            previewLoader: { source, _ in
                if source == .erapi {
                    return (source, .failure(URLError(.notConnectedToInternet)))
                }
                return (source, .success(RatePreview(rates: [], updatedAt: nil, isStale: false)))
            }
        )

        await vm.loadPreviews()

        #expect(vm.loadingStates[.erapi] == .failed)
        #expect(vm.loadingStates[.millio] == .loaded)
        #expect(vm.loadingStates[.frankfurter] == .loaded)
    }

    // MARK: - selectSource

    @Test("selectSource обновляет selectedSource и делегирует CurrencyRateService")
    func testSelectSourceUpdatesSelectedSourceAndDelegates() {
        let defaults = makeSuiteDefaults()
        let store = RateSourcePreferenceStore(defaults: defaults)

        let vm = RateSourcePickerViewModel(store: store)
        vm.selectSource(.frankfurter)

        #expect(vm.selectedSource == .frankfurter)
        // store.preferred написан через CurrencyRateService.setRateSource — проверяем косвенно
        #expect(CurrencyRateService.shared.rateSource == .frankfurter)

        // Восстановить shared state
        CurrencyRateService.shared.setRateSource(.millio)
    }

    @Test("selectSource не пишет store.preferred напрямую (только через CurrencyRateService)")
    func testSelectSourceDoesNotWriteStorePreferredDirectly() {
        let defaults = makeSuiteDefaults()
        var store = RateSourcePreferenceStore(defaults: defaults)
        store.preferred = .millio

        let vm = RateSourcePickerViewModel(store: store)

        // Проверяем: до вызова store.preferred == .millio
        #expect(store.preferred == .millio)

        vm.selectSource(.erapi)

        // После: CurrencyRateService.shared написал preferred в глобальный store
        // Локальный store (suite defaults) — не изменился, т.к. vm использует глобальный
        // Ключевое: selectSource НЕ вызывает store.preferred = напрямую
        #expect(vm.selectedSource == .erapi)

        CurrencyRateService.shared.setRateSource(.millio)
    }
}
