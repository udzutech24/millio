import Foundation
import SwiftData

@MainActor
final class StockBulkImportMatcher {
    private let modelContext: ModelContext
    private let instrumentResolver: MarketInstrumentResolver

    init(modelContext: ModelContext, marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared) {
        self.modelContext = modelContext
        self.instrumentResolver = MarketInstrumentResolver(client: marketDataClient)
    }

    func buildDraftRows(from parsedRows: [StockBulkImportParsedRow]) async -> [StockBulkImportRowDraft] {
        let localCatalog = loadLocalCatalog()
        let remoteCatalog = await loadRemoteCatalog(for: parsedRows)

        return parsedRows.map { parsedRow in
            let candidates = matchedCandidates(
                for: parsedRow,
                localCatalog: localCatalog,
                remoteCatalog: remoteCatalog
            )
            let selectedCandidate = candidates.count == 1 ? candidates[0] : nil

            return StockBulkImportRowDraft(
                rawLine: parsedRow.rawLine,
                tickerText: parsedRow.ticker,
                marketText: parsedRow.market ?? "",
                quantityText: parsedRow.quantity.map(Self.formatNumber) ?? "",
                buyPriceText: parsedRow.buyPrice.map(Self.formatNumber) ?? "",
                currentPriceText: "",
                sourceOrderIndex: parsedRow.sourceOrderIndex,
                candidates: candidates,
                selectedCandidate: selectedCandidate
            )
        }
    }

    private func loadLocalCatalog() -> [StockBulkImportCandidate] {
        let investments = (try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []
        return Array(Set(
            investments.compactMap { investment in
                guard investment.category == .stocks else { return nil }
                let symbol = resolvedTickerSymbol(from: investment.marketSymbol)
                guard !symbol.isEmpty else { return nil }
                return StockBulkImportCandidate(
                    symbol: symbol,
                    market: investment.marketExchange,
                    displayName: investment.name.isEmpty ? symbol : investment.name,
                    currency: "USD",
                    providerRaw: investment.marketProviderRaw
                )
            }
        ))
    }

    private func loadRemoteCatalog(for parsedRows: [StockBulkImportParsedRow]) async -> [String: [StockBulkImportCandidate]] {
        var remoteCatalog: [String: [StockBulkImportCandidate]] = [:]
        let uniqueTickers = Array(Set(parsedRows.map(\.ticker))).sorted().prefix(30)

        for ticker in uniqueTickers {
            do {
                let resolvedCandidates = try await instrumentResolver.resolveBulkImportCandidates(
                    query: ticker,
                    market: parsedRows.first(where: { $0.ticker == ticker })?.market,
                    outputSize: 30
                )
                remoteCatalog[ticker] = resolvedCandidates
            } catch {
                remoteCatalog[ticker] = []
            }
        }

        return remoteCatalog
    }

    private func matchedCandidates(
        for row: StockBulkImportParsedRow,
        localCatalog: [StockBulkImportCandidate],
        remoteCatalog: [String: [StockBulkImportCandidate]]
    ) -> [StockBulkImportCandidate] {
        let combined = Array(Set(localCatalog + (remoteCatalog[row.ticker] ?? [])))
        let tickerMatches = combined.filter { $0.normalizedSymbol == row.ticker.uppercased() }
        let rankedPool = tickerMatches.isEmpty ? combined : tickerMatches
        guard !rankedPool.isEmpty else { return [] }

        return MarketInstrumentCandidatePolicy.rankBulkImportCandidates(
            rankedPool,
            query: row.ticker,
            preferredMarket: row.market
        )
    }

    private func resolvedTickerSymbol(from storedSymbol: String?) -> String {
        guard let storedSymbol else { return "" }
        let trimmed = storedSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let lastSegment = trimmed.split(separator: ":").last {
            return String(lastSegment).uppercased()
        }
        if let firstSegment = trimmed.split(separator: ".").first {
            return String(firstSegment).uppercased()
        }
        return trimmed.uppercased()
    }

    private static func formatNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

@MainActor
struct StockBulkImportPersistenceService {
    let modelContext: ModelContext
    let marketDataClient: MarketDataClientProtocol

    init(modelContext: ModelContext, marketDataClient: MarketDataClientProtocol = MarketAPIClient.shared) {
        self.modelContext = modelContext
        self.marketDataClient = marketDataClient
    }

    func persist(
        drafts: [StockBulkImportRowDraft],
        includeInTotal: Bool,
        priority: InvestmentPriority,
        targetGroup: FinanceGroup?,
        mergeDuplicates: Bool
    ) async throws -> Int {
        // Если пользователь не выбрал группу — сохраняем в системную "Без группы".
        // Это важно: `FinanceAccount.group == nil` считается невалидным и будет очищаться нормализатором.
        let resolvedGroup = targetGroup ?? FinanceSystemGroups.ensureUngroupedGroup(in: modelContext)

        let resolvedRows = mergeDuplicates
            ? Self.mergeAddableRows(from: drafts)
            : Self.resolveAddableRows(from: drafts)
        guard !resolvedRows.isEmpty else { return 0 }

        let investments = (try? modelContext.fetch(FetchDescriptor<Investment>())) ?? []
        var investmentByIdentityKey: [String: Investment] = [:]
        investmentByIdentityKey.reserveCapacity(investments.count)
        for investment in investments where investment.archivedAt == nil && investment.category == .stocks {
            let key = investment.assetID ?? normalizedIdentityKey(symbol: investment.marketSymbol, exchange: investment.marketExchange)
            guard !key.isEmpty else { continue }
            investmentByIdentityKey[key] = investment
        }
        var financeAccounts = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []

        for resolvedRow in resolvedRows {
            let resolvedIdentity = MarketAssetIdentityResolver.resolve(
                category: .stocks,
                symbol: resolvedRow.candidate.storedSymbol,
                exchange: resolvedRow.candidate.normalizedMarket,
                instrumentName: resolvedRow.candidate.displayName,
                micCode: nil,
                instrumentType: "Common Stock",
                currency: resolvedRow.candidate.currency,
                country: nil,
                providerName: resolvedRow.candidate.providerRaw
            )
            let identityKey = resolvedIdentity?.assetID ?? resolvedRow.candidate.identityKey
            let latestPrice = await fetchLatestPrice(for: resolvedRow.candidate)
            let effectiveUnitPrice = resolvedRow.currentPrice ?? latestPrice ?? resolvedRow.buyPrice
            let amount = resolvedRow.quantity * effectiveUnitPrice

            if let existing = investmentByIdentityKey[identityKey] {
                existing.ensureUniqueID()
                existing.name = existing.name.isEmpty ? resolvedRow.candidate.displayName : existing.name
                existing.investmentType = .positive
                existing.category = .stocks
                existing.currency = "USD"
                existing.assetID = resolvedIdentity?.assetID ?? existing.assetID
                existing.marketCurrency = "USD"
                existing.marketExchange = resolvedRow.candidate.normalizedMarket
                existing.marketSymbol = resolvedRow.candidate.storedSymbol
                existing.marketProviderRaw = resolvedRow.candidate.providerRaw ?? existing.marketProviderRaw ?? "market-backend"
                existing.includeInTotal = includeInTotal
                existing.priority = priority
                _ = existing.applyBuy(quantity: resolvedRow.quantity, unitPrice: resolvedRow.buyPrice)
                existing.lastKnownUnitPrice = effectiveUnitPrice
                existing.lastKnownPriceUpdatedAt = Date()
                existing.amount = amountFor(
                    quantity: existing.marketQuantity ?? resolvedRow.quantity,
                    unitPrice: effectiveUnitPrice,
                    fallbackBuyPrice: resolvedRow.buyPrice
                )
                if let resolvedIdentity {
                    AssetCatalogStore(modelContext: modelContext).syncIfSupported(identity: resolvedIdentity)
                }
                updateFinanceAccountLink(for: existing, in: &financeAccounts, group: resolvedGroup)
                continue
            }

            let investment = Investment(
                name: resolvedRow.candidate.displayName,
                investmentType: .positive,
                category: .stocks,
                amount: amount,
                currency: "USD",
                includeInTotal: includeInTotal,
                priority: priority,
                isFavorite: false
            )
            investment.marketSymbol = resolvedRow.candidate.storedSymbol
            investment.assetID = resolvedIdentity?.assetID
            investment.marketExchange = resolvedRow.candidate.normalizedMarket
            investment.marketCurrency = "USD"
            investment.marketQuantity = resolvedRow.quantity
            investment.averagePurchaseUnitPrice = resolvedRow.buyPrice
            investment.totalPurchaseCost = resolvedRow.quantity * resolvedRow.buyPrice
            investment.lastKnownUnitPrice = effectiveUnitPrice
            investment.lastKnownPriceUpdatedAt = Date()
            investment.marketProviderRaw = resolvedRow.candidate.providerRaw ?? "market-backend"
            investment.amount = amountFor(
                quantity: resolvedRow.quantity,
                unitPrice: effectiveUnitPrice,
                fallbackBuyPrice: resolvedRow.buyPrice
            )

            modelContext.insert(investment)
            if let resolvedIdentity {
                AssetCatalogStore(modelContext: modelContext).syncIfSupported(identity: resolvedIdentity)
            }
            investmentByIdentityKey[identityKey] = investment
            let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            account.group = resolvedGroup
            modelContext.insert(account)
            financeAccounts.append(account)
        }

        try modelContext.save()
        return resolvedRows.count
    }

    private func fetchLatestPrice(for candidate: StockBulkImportCandidate) async -> Double? {
        for symbol in candidate.quoteLookupSymbols {
            do {
                if let latestPrice = try await marketDataClient.latestPrice(symbol: symbol, forceRefresh: false) {
                    return latestPrice
                }
            } catch {
                continue
            }
        }
        return nil
    }

    static func mergeAddableRows(from drafts: [StockBulkImportRowDraft]) -> [StockBulkImportResolvedRow] {
        var merged: [String: StockBulkImportResolvedRow] = [:]
        var order: [String] = []

        for draft in drafts.sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex }) {
            guard draft.isAddable,
                  let candidate = draft.selectedCandidate,
                  let quantity = draft.quantity,
                  let buyPrice = draft.buyPrice else {
                continue
            }

            let key = candidate.mergeKey
            if let existing = merged[key] {
                merged[key] = StockBulkImportResolvedRow(
                    candidate: existing.candidate,
                    quantity: existing.quantity + quantity,
                    buyPrice: existing.buyPrice,
                    currentPrice: existing.currentPrice ?? draft.currentPrice,
                    sourceOrderIndex: existing.sourceOrderIndex
                )
            } else {
                merged[key] = StockBulkImportResolvedRow(
                    candidate: candidate,
                    quantity: quantity,
                    buyPrice: buyPrice,
                    currentPrice: draft.currentPrice,
                    sourceOrderIndex: draft.sourceOrderIndex
                )
                order.append(key)
            }
        }

        return order.compactMap { merged[$0] }
    }

    static func resolveAddableRows(from drafts: [StockBulkImportRowDraft]) -> [StockBulkImportResolvedRow] {
        drafts
            .sorted(by: { $0.sourceOrderIndex < $1.sourceOrderIndex })
            .compactMap { draft in
                guard draft.isAddable,
                      let candidate = draft.selectedCandidate,
                      let quantity = draft.quantity,
                      let buyPrice = draft.buyPrice else {
                    return nil
                }
                return StockBulkImportResolvedRow(
                    candidate: candidate,
                    quantity: quantity,
                    buyPrice: buyPrice,
                    currentPrice: draft.currentPrice,
                    sourceOrderIndex: draft.sourceOrderIndex
                )
            }
    }

    private static func amountFor(quantity: Double, unitPrice: Double?, fallbackBuyPrice: Double) -> Double {
        quantity * (unitPrice ?? fallbackBuyPrice)
    }

    private func amountFor(quantity: Double, unitPrice: Double?, fallbackBuyPrice: Double) -> Double {
        Self.amountFor(quantity: quantity, unitPrice: unitPrice, fallbackBuyPrice: fallbackBuyPrice)
    }

    private func updateFinanceAccountLink(
        for investment: Investment,
        in existingAccounts: inout [FinanceAccount],
        group: FinanceGroup
    ) {
        if let account = existingAccounts.first(where: {
            $0.accountType == .investment && $0.accountID == investment.investmentUniqueID
        }) {
            account.group = group
            account.updatedAt = Date()
            return
        }

        let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
        account.group = group
        modelContext.insert(account)
        existingAccounts.append(account)
    }

    private func normalizedStoredSymbol(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? ""
    }

    private func normalizedIdentityKey(symbol: String?, exchange: String?) -> String {
        let normalizedSymbol = normalizedStoredSymbol(symbol)
        guard !normalizedSymbol.isEmpty else { return "" }

        if normalizedSymbol.contains(":") {
            let parts = normalizedSymbol.split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let marketKey = StockBulkImportCandidate.identityMarketKey(
                    for: StockBulkImportMarketNormalizer.normalize(parts[0])
                )
                return "\(marketKey)|\(parts[1])"
            }
        }

        let marketKey = StockBulkImportCandidate.identityMarketKey(
            for: StockBulkImportMarketNormalizer.normalize(exchange)
        )
        return "\(marketKey)|\(normalizedSymbol)"
    }
}
