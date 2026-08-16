//
//  FinanceMarketDataService.swift
//  millio
//
//  Создан в рамках Phase 6 декомпозиции FinanceViewModel.
//  Отвечает за обновление котировок акций (market quotes).
//

import Foundation
import SwiftData

// MARK: - StockRefreshIssues

struct StockRefreshIssues {
    var notFoundSymbols: Set<String> = []
    var priceUnavailableSymbols: Set<String> = []
    var providerErrorSymbols: Set<String> = []
    var authErrorSymbols: Set<String> = []
    var networkErrorSymbols: Set<String> = []
    var httpErrorSymbols: Set<String> = []
    var decodingErrorSymbols: Set<String> = []
    var clientErrorSymbols: Set<String> = []

    var hasIssues: Bool {
        !notFoundSymbols.isEmpty ||
        !priceUnavailableSymbols.isEmpty ||
        !providerErrorSymbols.isEmpty ||
        !authErrorSymbols.isEmpty ||
        !networkErrorSymbols.isEmpty ||
        !httpErrorSymbols.isEmpty ||
        !decodingErrorSymbols.isEmpty ||
        !clientErrorSymbols.isEmpty
    }

    mutating func remove(symbol: String) {
        notFoundSymbols.remove(symbol)
        priceUnavailableSymbols.remove(symbol)
        providerErrorSymbols.remove(symbol)
        authErrorSymbols.remove(symbol)
        networkErrorSymbols.remove(symbol)
        httpErrorSymbols.remove(symbol)
        decodingErrorSymbols.remove(symbol)
        clientErrorSymbols.remove(symbol)
    }
}

// MARK: - FinanceMarketDataService

@MainActor
final class FinanceMarketDataService {

    // MARK: - Constants

    static let quoteBatchSize = 8
    static let manualRefreshCooldown: TimeInterval = 15

    // MARK: - Dependencies

    private let modelContext: ModelContext
    private let marketDataClient: MarketDataClientProtocol
    private let nowProvider: () -> Date

    /// Callback: перезагрузить счета в VM после обновления цен
    private let onLoadAccounts: () -> Void
    /// Callback: обновить итоги групп
    private let onRefreshGroupTotals: () async -> Void

    // MARK: - State

    private(set) var lastManualStockRefreshAt: Date?

    // MARK: - Init

    init(
        modelContext: ModelContext,
        marketDataClient: MarketDataClientProtocol,
        nowProvider: @escaping () -> Date,
        onLoadAccounts: @escaping () -> Void,
        onRefreshGroupTotals: @escaping () async -> Void
    ) {
        self.modelContext = modelContext
        self.marketDataClient = marketDataClient
        self.nowProvider = nowProvider
        self.onLoadAccounts = onLoadAccounts
        self.onRefreshGroupTotals = onRefreshGroupTotals
    }

    // MARK: - Public

    /// Ручное обновление котировок с cooldown-защитой.
    /// Возвращает сообщение об ошибке если есть.
    @discardableResult
    func refreshStockPricesManual() async -> String? {
        let now = nowProvider()
        if let lastManualStockRefreshAt,
           now.timeIntervalSince(lastManualStockRefreshAt) < Self.manualRefreshCooldown {
            AppLogger.log(.info, category: "Finance", "Skipping manual stock refresh due to cooldown")
            return nil
        }
        lastManualStockRefreshAt = now
        let issues = await refreshStockPrices(forceRefresh: true)
        return stockRefreshIssueMessage(for: issues)
    }

    // MARK: - Private: Core Refresh

    @discardableResult
    func refreshStockPrices(forceRefresh: Bool) async -> StockRefreshIssues {
        let descriptor = FetchDescriptor<Investment>()
        let activeStocks = ((try? modelContext.fetch(descriptor)) ?? []).filter {
            $0.archivedAt == nil && $0.category == .stocks && $0.isMarketPriced
        }

        guard !activeStocks.isEmpty else {
            await onRefreshGroupTotals()
            return StockRefreshIssues()
        }

        var didUpdateAnyPrice = false
        var issues = StockRefreshIssues()

        var stockToLookupSymbols: [(stock: Investment, symbols: [String])] = []
        var symbolToStocks: [String: [Investment]] = [:]
        var allSymbolsOrdered: [String] = []
        var seenSymbols: Set<String> = []

        for stock in activeStocks {
            let lookupSymbols = stockQuoteRequestSymbols(for: stock)
            guard !lookupSymbols.isEmpty else {
                issues.notFoundSymbols.insert(stock.name.trimmingCharacters(in: .whitespacesAndNewlines))
                continue
            }
            stockToLookupSymbols.append((stock, lookupSymbols))
            for s in lookupSymbols {
                let key = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !seenSymbols.contains(key) {
                    seenSymbols.insert(key)
                    allSymbolsOrdered.append(key)
                }
                symbolToStocks[key, default: []].append(stock)
            }
        }

        var quotesBySymbol: [String: AssetSummary] = [:]
        var aborted = false
        var stocksAssignedIssueInCatch = Set<ObjectIdentifier>()

        for chunkStart in stride(from: 0, to: allSymbolsOrdered.count, by: Self.quoteBatchSize) {
            guard !aborted else { break }
            let chunk = Array(allSymbolsOrdered[chunkStart ..< min(chunkStart + Self.quoteBatchSize, allSymbolsOrdered.count)])
            do {
                let quotes = try await marketDataClient.fetchQuotes(symbols: chunk)
                var matchedRequestedSymbols: Set<String> = []

                for quote in quotes {
                    let keys = quote.quoteLookupKeys
                    for key in keys {
                        quotesBySymbol[key] = quote
                    }
                    matchedRequestedSymbols.formUnion(chunk.filter { keys.contains($0) })
                }

                let unmatchedRequestedSymbols = chunk.filter { matchedRequestedSymbols.contains($0) == false }
                if quotes.count != chunk.count || !unmatchedRequestedSymbols.isEmpty {
                    let requestedSymbolsLine = chunk.joined(separator: ",")
                    let unmatchedSymbolsLine = unmatchedRequestedSymbols.joined(separator: ",")
                    let returnedSummary = quotes.map { quote in
                        let canonical = quote.canonicalSymbol ?? "nil"
                        let provider = quote.providerSymbol ?? "nil"
                        let exchange = quote.exchange ?? "nil"
                        return "\(quote.symbol){status=\(quote.resolutionStatus.rawValue),canonical=\(canonical),provider=\(provider),exchange=\(exchange)}"
                    }
                    .joined(separator: ",")
                    AppLogger.log(
                        .warning,
                        category: "Finance",
                        "Quote batch mismatch requested=\(requestedSymbolsLine) returnedCount=\(quotes.count) unmatched=\(unmatchedSymbolsLine) returned=\(returnedSummary)"
                    )
                }
            } catch {
                let issueCategory = stockRefreshIssueCategory(for: error)
                let requestID = MarketDataErrorPresentation.requestID(for: error) ?? "none"
                AppLogger.log(
                    .warning,
                    category: "Finance",
                    "Batch quote failed: category=\(issueCategory.rawValue) requestId=\(requestID) error=\(error.localizedDescription)"
                )
                if shouldAbortQuoteAliasRefresh(after: error) {
                    aborted = true
                }
                for symbol in chunk {
                    for stock in symbolToStocks[symbol] ?? [] {
                        if stocksAssignedIssueInCatch.insert(ObjectIdentifier(stock)).inserted {
                            assignStockRefreshIssue(issueCategory, symbol: stockDisplaySymbol(stock), to: &issues)
                        }
                    }
                }
            }
        }

        for (stock, lookupSymbols) in stockToLookupSymbols {
            var refreshed = false
            var lastIssueCategory: MarketDataIssueCategory?
            for symbol in lookupSymbols {
                let key = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                guard let quote = quotesBySymbol[key] else { continue }
                switch quote.resolutionStatus {
                case .fresh, .stale:
                    guard let price = quote.price, price > 0 else {
                        if lastIssueCategory == nil {
                            lastIssueCategory = MarketDataErrorPresentation.category(for: quote) ?? .priceUnavailable
                        }
                        continue
                    }
                    stock.lastKnownUnitPrice = price
                    stock.lastKnownPriceUpdatedAt = quote.updatedAtDate ?? Date()
                    stock.marketQuoteLookupKey = quote.canonicalQuoteLookupKey
                    stock.marketExchange = quote.exchange ?? stock.marketExchange
                    stock.marketMICCode = quote.micCode ?? stock.marketMICCode
                    stock.marketCurrency = quote.currency ?? stock.marketCurrency
                    stock.marketProviderRaw = quote.providerSymbol == nil ? stock.marketProviderRaw : "market-backend"
                    stock.recalculateAmountFromPosition()
                    stock.updatedAt = Date()
                    didUpdateAnyPrice = true
                    refreshed = true
                    issues.remove(symbol: stockDisplaySymbol(stock))
                    break
                case .notFound:
                    if lastIssueCategory == nil {
                        lastIssueCategory = .notFound
                    }
                    continue
                case .providerError:
                    if lastIssueCategory == nil {
                        lastIssueCategory = .providerError
                    }
                    AppLogger.log(.warning, category: "Finance", "Provider error while refreshing stock quote for \(symbol)")
                    continue
                }
            }
            if !refreshed, !stocksAssignedIssueInCatch.contains(ObjectIdentifier(stock)) {
                assignStockRefreshIssue(lastIssueCategory, symbol: stockDisplaySymbol(stock), to: &issues)
            }
        }

        if didUpdateAnyPrice {
            do {
                try modelContext.save()
                // Historical chart and live account totals share the investment price evidence.
                // Notify the existing single refresh route only after the transaction commits.
                EventBus.shared.publish(FinanceEvent.investmentsUpdated)
            } catch {
                AppLogger.log(.error, category: "Finance", "Failed to save refreshed stock quotes: \(error.localizedDescription)")
            }
        }

        onLoadAccounts()
        await onRefreshGroupTotals()
        return normalizedStockRefreshIssues(issues)
    }

    // MARK: - Private: Issue Helpers

    private func shouldAbortQuoteAliasRefresh(after error: Error) -> Bool {
        guard let marketError = error as? MarketAPIClientError else {
            return false
        }

        switch marketError {
        case .backend(let statusCode, let message, _):
            return statusCode == 429 || message.localizedCaseInsensitiveContains("Too Many Requests")
        case .transport(let message):
            return message.localizedCaseInsensitiveContains("Too Many Requests")
        default:
            return false
        }
    }

    private func normalizedStockRefreshIssues(_ issues: StockRefreshIssues) -> StockRefreshIssues {
        StockRefreshIssues(
            notFoundSymbols: normalizedStockRefreshSymbols(issues.notFoundSymbols),
            priceUnavailableSymbols: normalizedStockRefreshSymbols(issues.priceUnavailableSymbols),
            providerErrorSymbols: normalizedStockRefreshSymbols(issues.providerErrorSymbols),
            authErrorSymbols: normalizedStockRefreshSymbols(issues.authErrorSymbols),
            networkErrorSymbols: normalizedStockRefreshSymbols(issues.networkErrorSymbols),
            httpErrorSymbols: normalizedStockRefreshSymbols(issues.httpErrorSymbols),
            decodingErrorSymbols: normalizedStockRefreshSymbols(issues.decodingErrorSymbols),
            clientErrorSymbols: normalizedStockRefreshSymbols(issues.clientErrorSymbols)
        )
    }

    private func normalizedStockRefreshSymbols(_ values: Set<String>) -> Set<String> {
        Set(
            values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    func stockRefreshIssueMessage(for issues: StockRefreshIssues) -> String? {
        guard issues.hasIssues else { return nil }
        if !issues.authErrorSymbols.isEmpty {
            return MarketDataErrorPresentation.message(for: .authError)
        }
        return nil
    }

    private func appendStockRefreshSymbols(
        _ values: [String],
        category: MarketDataIssueCategory,
        to parts: inout [String]
    ) {
        guard !values.isEmpty else { return }
        let label = MarketDataErrorPresentation.listLabel(for: category)
        parts.append("\(label): \(values.joined(separator: ", "))")
    }

    private func stockRefreshIssueCategory(for error: Error) -> MarketDataIssueCategory {
        MarketDataErrorPresentation.category(for: error)
    }

    private func assignStockRefreshIssue(
        _ category: MarketDataIssueCategory?,
        symbol: String,
        to issues: inout StockRefreshIssues
    ) {
        switch category ?? .notFound {
        case .notFound:
            issues.notFoundSymbols.insert(symbol)
        case .priceUnavailable:
            issues.priceUnavailableSymbols.insert(symbol)
        case .providerError:
            issues.providerErrorSymbols.insert(symbol)
        case .authError:
            issues.authErrorSymbols.insert(symbol)
        case .networkError:
            issues.networkErrorSymbols.insert(symbol)
        case .httpError:
            issues.httpErrorSymbols.insert(symbol)
        case .decodeError:
            issues.decodingErrorSymbols.insert(symbol)
        case .clientError:
            issues.clientErrorSymbols.insert(symbol)
        }
    }

    private func stockQuoteRequestSymbols(for investment: Investment) -> [String] {
        guard let symbol = ProviderInstrumentResolver(modelContext: modelContext)
            .preferredRefreshSymbol(for: investment) else {
            return []
        }
        return [symbol]
    }

    func stockDisplaySymbol(_ investment: Investment) -> String {
        investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
    }
}
