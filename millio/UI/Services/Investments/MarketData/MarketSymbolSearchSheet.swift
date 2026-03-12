import SwiftUI
import Combine

enum MarketSymbolFilter: Sendable {
    case stocks
    case crypto

    var navigationTitle: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search_title_stocks"
        case .crypto:
            return "finances.market.search_title_crypto"
        }
    }

    var searchPrompt: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search_prompt_ticker"
        case .crypto:
            return "finances.market.search_prompt_pair"
        }
    }

    var instructionText: LocalizedStringKey {
        switch self {
        case .stocks:
            return "finances.market.search.instructions_stocks"
        case .crypto:
            return "finances.market.search.instructions_crypto"
        }
    }

    var topSymbols: [TwelveDataSymbol] {
        switch self {
        case .stocks:
            return [
                TwelveDataSymbol(symbol: "AAPL", instrumentName: "Apple Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "MSFT", instrumentName: "Microsoft Corporation", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "NVDA", instrumentName: "NVIDIA Corporation", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "AMZN", instrumentName: "Amazon.com, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "GOOGL", instrumentName: "Alphabet Inc. Class A", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "META", instrumentName: "Meta Platforms, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "TSLA", instrumentName: "Tesla, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "SPY", instrumentName: "SPDR S&P 500 ETF Trust", exchange: "NYSE", micCode: "ARCX", instrumentType: "ETF", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "QQQ", instrumentName: "Invesco QQQ Trust", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "ETF", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "AMD", instrumentName: "Advanced Micro Devices, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "PLTR", instrumentName: "Palantir Technologies Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD"),
                TwelveDataSymbol(symbol: "NFLX", instrumentName: "Netflix, Inc.", exchange: "NASDAQ", micCode: "XNAS", instrumentType: "Common Stock", country: "United States", currency: "USD")
            ]
        case .crypto:
            return [
                TwelveDataSymbol(symbol: "BTC/USD", instrumentName: "Bitcoin / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "ETH/USD", instrumentName: "Ethereum / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "SOL/USD", instrumentName: "Solana / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "XRP/USD", instrumentName: "XRP / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "ADA/USD", instrumentName: "Cardano / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "DOGE/USD", instrumentName: "Dogecoin / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "BNB/USD", instrumentName: "BNB / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "AVAX/USD", instrumentName: "Avalanche / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "DOT/USD", instrumentName: "Polkadot / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD"),
                TwelveDataSymbol(symbol: "LINK/USD", instrumentName: "Chainlink / US Dollar", exchange: "CRYPTO", micCode: nil, instrumentType: "Cryptocurrency", country: nil, currency: "USD")
            ]
        }
    }

    func matches(_ symbol: TwelveDataSymbol) -> Bool {
        guard let type = symbol.normalizedInstrumentType, !type.isEmpty else {
            return true
        }

        switch self {
        case .stocks:
            return type.contains("stock") || type.contains("equity") || type.contains("etf")
        case .crypto:
            return type.contains("crypto") || type.contains("digital") || type.contains("coin")
        }
    }
}

enum MarketSymbolSearchFormatter {
    static func prepareResults(
        _ symbols: [TwelveDataSymbol],
        filter: MarketSymbolFilter,
        query: String
    ) -> [TwelveDataSymbol] {
        let normalizedQuery = normalized(query)

        return deduplicated(symbols.filter { filter.matches($0) })
            .sorted { lhs, rhs in
                compareStable(lhs, rhs, query: normalizedQuery)
            }
    }

    static func deduplicated(_ symbols: [TwelveDataSymbol]) -> [TwelveDataSymbol] {
        var orderedKeys: [String] = []
        var bestByKey: [String: TwelveDataSymbol] = [:]

        for symbol in symbols {
            let key = dedupeIdentityKey(for: symbol)
            if let current = bestByKey[key] {
                if metadataScore(symbol) > metadataScore(current) {
                    bestByKey[key] = symbol
                }
            } else {
                orderedKeys.append(key)
                bestByKey[key] = symbol
            }
        }

        return orderedKeys.compactMap { bestByKey[$0] }
    }

    static func compareStable(_ lhs: TwelveDataSymbol, _ rhs: TwelveDataSymbol, query: String) -> Bool {
        let lhsRank = relevanceRank(for: lhs, query: query)
        let rhsRank = relevanceRank(for: rhs, query: query)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let lhsSymbol = normalized(lhs.symbol)
        let rhsSymbol = normalized(rhs.symbol)
        if lhsSymbol.count != rhsSymbol.count {
            return lhsSymbol.count < rhsSymbol.count
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private static func relevanceRank(for symbol: TwelveDataSymbol, query: String) -> Int {
        guard !query.isEmpty else { return 0 }

        let ticker = normalized(symbol.symbol)
        let name = normalized(symbol.displayName)

        if ticker == query { return 0 }
        if ticker.hasPrefix(query) { return 1 }
        if name.hasPrefix(query) { return 2 }
        if ticker.contains(query) { return 3 }
        if name.contains(query) { return 4 }
        return 5
    }

    // We collapse backend duplicates by market identity and keep the richest payload.
    static func dedupeIdentityKey(for symbol: TwelveDataSymbol) -> String {
        let quoteKey = normalized(symbol.canonicalQuoteLookupKey)
        let market = normalized(symbol.exchange ?? symbol.micCode ?? "")
        let type = normalized(symbol.instrumentType ?? "")
        let currency = normalized(symbol.currency ?? "")
        let name = normalized(symbol.displayName)
        return [quoteKey, market, type, currency, name].joined(separator: "|")
    }

    private static func metadataScore(_ symbol: TwelveDataSymbol) -> Int {
        [
            symbol.instrumentName,
            symbol.exchange,
            symbol.micCode,
            symbol.instrumentType,
            symbol.country,
            symbol.currency
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .count
    }

    static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

@MainActor
final class MarketSymbolSearchViewModel: ObservableObject {
    static let minimumRemoteQueryLength = MarketSymbolSearchEngine.minimumRemoteQueryLength
    private static let maxCachedQueries = 24

    @Published var searchText: String = ""
    @Published private(set) var results: [TwelveDataSymbol] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?

    private let filter: MarketSymbolFilter
    private let resolver: MarketInstrumentResolver
    private var searchTask: Task<Void, Never>?
    private var cachedResultsByQuery: [String: [TwelveDataSymbol]] = [:]
    private var cachedQueryOrder: [String] = []

    init(client: MarketDataClientProtocol, filter: MarketSymbolFilter) {
        self.filter = filter
        self.resolver = MarketInstrumentResolver(client: client)
    }

    func updateSearch() {
        searchTask?.cancel()

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        guard query.count >= Self.minimumRemoteQueryLength else {
            results = []
            errorMessage = nil
            isLoading = false
            return
        }

        let queryCacheKey = MarketSymbolSearchEngine.normalize(query)
        let localResults = resolver.localResults(query: query, filter: filter)
        let cachedResults = cachedResultsByQuery[queryCacheKey] ?? []
        let seededResults = MarketSymbolSearchEngine.prepareResults(
            remoteSymbols: cachedResults,
            filter: filter,
            query: query
        )
        results = seededResults.isEmpty ? localResults : seededResults
        errorMessage = nil

        if MarketSymbolSearchEngine.shouldSkipRemoteSearch(
            filter: filter,
            query: query,
            localResults: localResults
        ) {
            isLoading = false
            return
        }

        isLoading = true

        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(Int(MarketSymbolSearchEngine.remoteSearchDebounceMilliseconds)))
                guard !Task.isCancelled else { return }

                let fetched = try await self.resolver.resolveSymbols(
                    query: query,
                    filter: self.filter,
                    outputSize: 20
                )
                guard !Task.isCancelled else { return }

                self.results = fetched
                self.storeCachedResults(fetched, for: queryCacheKey)
                self.isLoading = false
                self.errorMessage = nil
            } catch is CancellationError {
                return
            } catch {
                let fallbackResults = self.resolver.localResults(query: query, filter: self.filter)
                self.results = fallbackResults
                self.isLoading = false
                self.errorMessage = self.userFacingSearchErrorMessage(for: error, query: query, hasFallbackResults: !fallbackResults.isEmpty)
            }
        }
    }

    func cancelOngoingSearch() {
        searchTask?.cancel()
    }

    var emptyStateHintText: String {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return String(localized: "finances.market.search.start_hint")
        }

        if query.count < Self.minimumRemoteQueryLength {
            return String(
                format: String(localized: "finances.market.search.min_chars_format"),
                Self.minimumRemoteQueryLength
            )
        }

        return String(localized: "finances.market.search_hint")
    }

    private func userFacingSearchErrorMessage(for error: Error, query: String, hasFallbackResults: Bool) -> String? {
        if hasFallbackResults {
            return nil
        }

        if isRateLimitError(error) {
            return String(localized: "finances.market.search.rate_limit")
        }

        return error.localizedDescription
    }

    private func isRateLimitError(_ error: Error) -> Bool {
        if case let MarketAPIClientError.backend(statusCode, message) = error {
            if statusCode == 429 {
                return true
            }

            let normalizedMessage = message.lowercased()
            return normalizedMessage.contains("too many requests") || normalizedMessage.contains("throttle")
        }

        let normalizedDescription = error.localizedDescription.lowercased()
        return normalizedDescription.contains("too many requests") || normalizedDescription.contains("throttle")
    }

    private func storeCachedResults(_ results: [TwelveDataSymbol], for queryCacheKey: String) {
        guard !queryCacheKey.isEmpty else { return }
        cachedResultsByQuery[queryCacheKey] = results
        cachedQueryOrder.removeAll { $0 == queryCacheKey }
        cachedQueryOrder.append(queryCacheKey)

        while cachedQueryOrder.count > Self.maxCachedQueries {
            let oldest = cachedQueryOrder.removeFirst()
            cachedResultsByQuery.removeValue(forKey: oldest)
        }
    }
}

struct MarketSymbolSearchSheet: View {
    let filter: MarketSymbolFilter
    let onSelect: (TwelveDataSymbol) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.isSearching) private var isSearching
    @StateObject private var viewModel: MarketSymbolSearchViewModel
    @State private var showSupportContactSheet = false

    private let quickPickColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    init(
        filter: MarketSymbolFilter,
        client: MarketDataClientProtocol = MarketAPIClient.shared,
        onSelect: @escaping (TwelveDataSymbol) -> Void
    ) {
        self.filter = filter
        self.onSelect = onSelect
        _viewModel = StateObject(wrappedValue: MarketSymbolSearchViewModel(client: client, filter: filter))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                GradientBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        if shouldShowQuickPicks {
                            quickPicksSection
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                        }

                        contentView
                            .frame(maxWidth: .infinity, alignment: .top)

                        instructionsCard
                            .padding(.horizontal, 16)
                            .padding(.top, shouldShowQuickPicks ? 8 : 0)
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle(filter.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .foregroundStyle(AppColors.textPrimary)
                }
            }
            .searchable(
                text: $viewModel.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: filter.searchPrompt
            )
            .onChange(of: viewModel.searchText) { _, _ in
                viewModel.updateSearch()
            }
            .onDisappear {
                viewModel.cancelOngoingSearch()
            }
            .sheet(isPresented: $showSupportContactSheet) {
                SupportContactSheet()
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isLoading && viewModel.results.isEmpty {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else if let errorMessage = viewModel.errorMessage,
                      viewModel.results.isEmpty {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                        .multilineTextAlignment(.center)
                    Text(viewModel.emptyStateHintText)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 40)
            } else if viewModel.results.isEmpty {
                VStack(spacing: 8) {
                    Text(String(localized: "finances.market.search_empty"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    Text(viewModel.emptyStateHintText)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.top, 24)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, item in
                        marketSymbolRow(item)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                        if index < viewModel.results.count - 1 {
                            Divider()
                                .overlay(Color.white.opacity(0.08))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var shouldShowQuickPicks: Bool {
        viewModel.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSearching
    }

    private var quickPicksSection: some View {
        LazyVGrid(columns: quickPickColumns, spacing: 10) {
            ForEach(filter.topSymbols) { item in
                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.symbol)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppColors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        if let exchange = item.exchange,
                           !exchange.isEmpty {
                            Text(exchange)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(AppColors.textTertiary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 74, alignment: .leading)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.07),
                                        Color.white.opacity(0.035)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.09), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func marketSymbolRow(_ item: TwelveDataSymbol) -> some View {
        Button {
            onSelect(item)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    if let exchange = item.exchange,
                       !exchange.isEmpty {
                        Text(exchange)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }

                Text(item.displayName)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)

                if let currency = item.currency,
                   !currency.isEmpty {
                    Text(currency)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.5))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(filter.instructionText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "message.badge.waveform.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 8) {
                    Text("finances.market.search.support_hint")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button(String(localized: "finances.market.search.contact_action")) {
                        showSupportContactSheet = true
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.brandPrimary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.06),
                            Color.white.opacity(0.035)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
