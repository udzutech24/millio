import Foundation
import SwiftData

@MainActor
final class StockBulkImportMatcher {
    private let modelContext: ModelContext
    private let marketDataClient: MarketDataClientProtocol

    init(modelContext: ModelContext, marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared) {
        self.modelContext = modelContext
        self.marketDataClient = marketDataClient
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
                let symbols = try await marketDataClient.searchSymbols(query: ticker, outputSize: 30)
                let exactCandidates = symbols.compactMap { symbol -> StockBulkImportCandidate? in
                    guard symbol.symbol.uppercased() == ticker.uppercased() else { return nil }
                    let type = symbol.normalizedInstrumentType ?? ""
                    guard type.contains("stock") || type.contains("equity") || type.contains("etf") || type.isEmpty else {
                        return nil
                    }
                    return StockBulkImportCandidate(
                        symbol: symbol.symbol,
                        market: symbol.exchange,
                        displayName: symbol.displayName,
                        currency: "USD",
                        providerRaw: "twelvedata"
                    )
                }
                remoteCatalog[ticker] = Array(Set(exactCandidates))
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
        let symbolMatches = combined.filter { $0.normalizedSymbol == row.ticker.uppercased() }
        guard !symbolMatches.isEmpty else { return [] }

        guard let normalizedMarket = StockBulkImportMarketNormalizer.normalize(row.market) else {
            return symbolMatches.sorted(by: candidateSort)
        }

        if normalizedMarket == "US" {
            let usMatches = symbolMatches.filter {
                guard let market = $0.normalizedMarket else { return false }
                return ["NASDAQ", "NYSE", "AMEX", "BATS", "IEX", "US"].contains(market)
            }
            return (usMatches.isEmpty ? symbolMatches : usMatches).sorted(by: candidateSort)
        }

        let exactMarketMatches = symbolMatches.filter {
            $0.normalizedMarket == normalizedMarket
        }
        return (exactMarketMatches.isEmpty ? symbolMatches : exactMarketMatches).sorted(by: candidateSort)
    }

    private func resolvedTickerSymbol(from storedSymbol: String?) -> String {
        guard let storedSymbol else { return "" }
        let trimmed = storedSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if let lastSegment = trimmed.split(separator: ":").last {
            return String(lastSegment).uppercased()
        }
        return trimmed.uppercased()
    }

    private var candidateSort: (StockBulkImportCandidate, StockBulkImportCandidate) -> Bool {
        { lhs, rhs in
            let leftMarket = lhs.normalizedMarket ?? "ZZZ"
            let rightMarket = rhs.normalizedMarket ?? "ZZZ"
            if leftMarket != rightMarket {
                return leftMarket < rightMarket
            }
            return lhs.displayName < rhs.displayName
        }
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

    init(modelContext: ModelContext, marketDataClient: MarketDataClientProtocol = TwelveDataClient.shared) {
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
        var investmentByStoredSymbol: [String: Investment] = [:]
        investmentByStoredSymbol.reserveCapacity(investments.count)
        for investment in investments where investment.archivedAt == nil && investment.category == .stocks {
            let key = normalizedStoredSymbol(investment.marketSymbol)
            guard !key.isEmpty else { continue }
            investmentByStoredSymbol[key] = investment
        }
        var financeAccounts = (try? modelContext.fetch(FetchDescriptor<FinanceAccount>())) ?? []

        for resolvedRow in resolvedRows {
            let latestPrice = (try? await marketDataClient.latestPrice(symbol: resolvedRow.candidate.storedSymbol, forceRefresh: false)) ?? nil
            let effectiveUnitPrice = resolvedRow.currentPrice ?? latestPrice ?? resolvedRow.buyPrice
            let amount = resolvedRow.quantity * effectiveUnitPrice

            if let existing = investmentByStoredSymbol[resolvedRow.candidate.storedSymbol] {
                existing.ensureUniqueID()
                existing.name = existing.name.isEmpty ? resolvedRow.candidate.displayName : existing.name
                existing.investmentType = .positive
                existing.category = .stocks
                existing.currency = "USD"
                existing.marketCurrency = "USD"
                existing.marketExchange = resolvedRow.candidate.normalizedMarket
                existing.marketSymbol = resolvedRow.candidate.storedSymbol
                existing.marketProviderRaw = resolvedRow.candidate.providerRaw ?? existing.marketProviderRaw ?? "twelvedata"
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
            investment.marketExchange = resolvedRow.candidate.normalizedMarket
            investment.marketCurrency = "USD"
            investment.marketQuantity = resolvedRow.quantity
            investment.averagePurchaseUnitPrice = resolvedRow.buyPrice
            investment.totalPurchaseCost = resolvedRow.quantity * resolvedRow.buyPrice
            investment.lastKnownUnitPrice = effectiveUnitPrice
            investment.lastKnownPriceUpdatedAt = Date()
            investment.marketProviderRaw = resolvedRow.candidate.providerRaw ?? "twelvedata"
            investment.amount = amountFor(
                quantity: resolvedRow.quantity,
                unitPrice: effectiveUnitPrice,
                fallbackBuyPrice: resolvedRow.buyPrice
            )

            modelContext.insert(investment)
            investmentByStoredSymbol[resolvedRow.candidate.storedSymbol] = investment
            let account = FinanceAccount(accountType: .investment, accountID: investment.investmentUniqueID)
            account.group = resolvedGroup
            modelContext.insert(account)
            financeAccounts.append(account)
        }

        try modelContext.save()
        return resolvedRows.count
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
}
