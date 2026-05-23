//
//  RateSourcePickerViewModel.swift
//  millio
//

import Foundation
import Combine

struct RatePreview: Equatable {
    let rates: [(code: String, rate: Double)]
    let updatedAt: Date?
    let isStale: Bool

    static func == (lhs: RatePreview, rhs: RatePreview) -> Bool {
        guard lhs.updatedAt == rhs.updatedAt, lhs.isStale == rhs.isStale else { return false }
        guard lhs.rates.count == rhs.rates.count else { return false }
        return zip(lhs.rates, rhs.rates).allSatisfy { l, r in l.code == r.code && l.rate == r.rate }
    }
}

@MainActor
final class RateSourcePickerViewModel: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed }

    @Published var previews: [RateSource: RatePreview] = [:]
    @Published var loadingStates: [RateSource: LoadState] = [:]
    @Published var selectedSource: RateSource

    let store: RateSourcePreferenceStore
    private let primaryCurrencyCode: String
    private let favoriteCurrencyCodes: [String]

    var previewLoader: (RateSource, String) async -> (RateSource, Result<RatePreview, Error>)

    init(
        store: RateSourcePreferenceStore = .shared,
        primaryCurrencyCode: String = SettingsManager.shared.primaryCurrencyCode,
        favoriteCurrencyCodes: [String] = SettingsManager.shared.favoriteCurrencyCodes,
        previewLoader: ((RateSource, String) async -> (RateSource, Result<RatePreview, Error>))? = nil
    ) {
        self.store = store
        self.primaryCurrencyCode = primaryCurrencyCode
        self.favoriteCurrencyCodes = favoriteCurrencyCodes
        self.selectedSource = store.preferred
        self.previewLoader = previewLoader ?? { source, primary in
            await RateSourcePickerViewModel.defaultFetchPreview(source: source, primaryCode: primary)
        }
    }

    // MARK: - Visible Sources

    static func visibleSources(
        primaryCurrencyCode: String,
        favoriteCurrencyCodes: [String],
        appLocale: Locale = AppLocalization.currentAppLocale
    ) -> [RateSource] {
        let rubInProfile = primaryCurrencyCode.uppercased() == "RUB"
            || favoriteCurrencyCodes.contains { $0.uppercased() == "RUB" }
        let isRussianLocale = appLocale.language.languageCode?.identifier == "ru"
        return RateSource.allCases.filter { source in
            if source == .cbr { return rubInProfile || isRussianLocale }
            return true
        }
    }

    func visibleSources() -> [RateSource] {
        Self.visibleSources(
            primaryCurrencyCode: primaryCurrencyCode,
            favoriteCurrencyCodes: favoriteCurrencyCodes
        )
    }

    // MARK: - Load Previews

    func loadPreviews() async {
        let sources = visibleSources()
        for source in sources { loadingStates[source] = .loading }

        let loader = previewLoader
        let primary = primaryCurrencyCode

        await withTaskGroup(of: (RateSource, Result<RatePreview, Error>).self) { group in
            for source in sources {
                group.addTask { await loader(source, primary) }
            }
            for await (source, result) in group {
                switch result {
                case .success(let preview):
                    previews[source] = preview
                    loadingStates[source] = .loaded
                case .failure:
                    loadingStates[source] = .failed
                }
            }
        }
    }

    // MARK: - Select

    func selectSource(_ source: RateSource) {
        selectedSource = source
        CurrencyRateService.shared.setRateSource(source)
        CurrencyWidgetSyncService.setString(source.rawValue, forKey: CurrencyWidgetShared.Keys.rateSource)
    }

    // MARK: - Preview Fetch

    private static func defaultFetchPreview(
        source: RateSource,
        primaryCode: String
    ) async -> (RateSource, Result<RatePreview, Error>) {
        let service = CurrencyRateService(rateSource: source)
        await service.forceRefreshRates()

        let codes = ["USD", "EUR", "GBP", "JPY", "CNY"]
            .filter { $0 != primaryCode.uppercased() }
        // Показываем «обменный» формат: сколько единиц primaryCode за 1 единицу иностранной валюты.
        // Например при primary=RUB: USD → 70.92, а не 0.0141.
        let rates = codes.prefix(4).compactMap { code -> (code: String, rate: Double)? in
            guard let rate = service.getCachedRate(from: code, to: primaryCode) else { return nil }
            return (code: code, rate: rate)
        }

        let tsKey = "rate_repo_fetched_at_\(source.rawValue)"
        let ts = UserDefaults.standard.double(forKey: tsKey)
        let updatedAt: Date? = ts > 0 ? Date(timeIntervalSince1970: ts) : nil
        let isStale = updatedAt.map { Date().timeIntervalSince($0) > 86400 } ?? false

        return (source, .success(RatePreview(rates: Array(rates), updatedAt: updatedAt, isStale: isStale)))
    }
}
