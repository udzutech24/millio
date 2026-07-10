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
        let legacyCandidates = investments.compactMap { investment -> StockBulkImportCandidate? in
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

        // Ядро (план 6b «Путь B», Фаза 3): после перевода `persist(...)` на `AccountsCoreService`
        // новые позиции больше не попадают в легаси `Investment` — без этого блока повторный импорт
        // уже добавленного core-тикера не подсказывался бы автодополнением как «уже есть».
        let coreAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let coreCandidates = coreAccounts.compactMap { account -> StockBulkImportCandidate? in
            guard account.kind == .marketInvestment, let meta = account.marketMeta else { return nil }
            let symbol = resolvedTickerSymbol(from: meta.symbol)
            guard !symbol.isEmpty else { return nil }
            return StockBulkImportCandidate(
                symbol: symbol,
                market: nil,
                displayName: account.name.isEmpty ? symbol : account.name,
                currency: "USD",
                providerRaw: nil
            )
        }

        return Array(Set(legacyCandidates + coreCandidates))
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

    /// Импорт создаёт СЧЕТА НОВОГО ЯДРА (`AccountKind.marketInvestment`) — план 6b «Путь B»,
    /// Фаза 3: перевод живых писателей легаси на `AccountsCoreService`, легаси `Investment`/
    /// `FinanceAccount` больше не создаются. `priority` остаётся в сигнатуре ради совместимости
    /// вызова из `StockBulkImportSheet` — ядро не хранит приоритет инвестиции, тот же осознанный
    /// пробел, что и в `FinanceAddAccountView.createAssetAccountOnNewCore` (единственный уже
    /// живущий core-путь создания рыночного счёта), не новая деградация.
    func persist(
        drafts: [StockBulkImportRowDraft],
        includeInTotal: Bool,
        priority: InvestmentPriority,
        targetGroup: FinanceGroup?,
        mergeDuplicates: Bool
    ) async throws -> Int {
        let resolvedGroup = AccountsCoreAdditionBridge.resolveAccountGroup(matching: targetGroup, in: modelContext)
        let service = AccountsCoreService(modelContext: modelContext)

        let resolvedRows = mergeDuplicates
            ? Self.mergeAddableRows(from: drafts)
            : Self.resolveAddableRows(from: drafts)
        guard !resolvedRows.isEmpty else { return 0 }

        // Дедуп по СИМВОЛУ — единственная identity, которую хранит `MarketMeta` ядра (см.
        // `AccountMeta.swift`). Легаси умел различать один тикер на разных биржах через
        // `assetID`/`exchange` (`MarketAssetIdentityResolver`) — ядро этого не переносит; при
        // 1–2 юзерах и уже принятом MVP-пробеле (план §3) это не блокер Фазы 3.
        let existingAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        var accountBySymbol: [String: Account] = [:]
        for account in existingAccounts where account.archivedAt == nil && account.kind == .marketInvestment {
            if let symbol = account.marketMeta?.symbol, !symbol.isEmpty {
                accountBySymbol[symbol.uppercased()] = account
            }
        }

        var importedCount = 0
        for resolvedRow in resolvedRows {
            // Символ БЕЗ префикса биржи (`normalizedSymbol`, не `storedSymbol` вида `MARKET:TICKER`) —
            // тот же формат, что уже хранит `MarketMeta.symbol` у единственного другого писателя
            // ядра (`FinanceAddAccountView`, тикер-пикер кладёт `symbol.symbol` без префикса).
            // `storedSymbol` сломал бы `AccountMarketPriceService.refreshTodayPrices()` — он шлёт
            // `meta.symbol` в `fetchQuotes` буквально, без парсинга префикса биржи.
            let symbol = resolvedRow.candidate.normalizedSymbol
            guard !symbol.isEmpty else { continue }

            // Синк в общий каталог тикеров — не привязан к легаси/ядру, оставлен без изменений.
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
            if let resolvedIdentity {
                AssetCatalogStore(modelContext: modelContext).syncIfSupported(identity: resolvedIdentity)
            }

            let quantity = Decimal(resolvedRow.quantity)
            let unitPrice = Decimal(resolvedRow.buyPrice)

            if let existing = accountBySymbol[symbol.uppercased()] {
                existing.includeInTotal = includeInTotal
                existing.group = resolvedGroup
                try service.buy(account: existing, quantity: quantity, unitPrice: unitPrice)
            } else {
                let meta = AccountsCoreAdditionBridge.marketMeta(symbol: symbol, category: .stocks)
                // currency жёстко "USD" — легаси-импортёр всегда так делал (`Investment(..., currency: "USD")`),
                // не полагаясь на `candidate.currency` (может быть пустым для тикера в USD-выражении).
                let account = try service.createAccount(
                    name: resolvedRow.candidate.displayName.isEmpty ? symbol : resolvedRow.candidate.displayName,
                    kind: .marketInvestment,
                    currency: "USD",
                    openingBalance: 0,
                    group: resolvedGroup,
                    marketMeta: meta
                )
                account.includeInTotal = includeInTotal
                try service.buy(account: account, quantity: quantity, unitPrice: unitPrice)
                accountBySymbol[symbol.uppercased()] = account
            }

            importedCount += 1
        }

        try modelContext.save()
        return importedCount
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

}
