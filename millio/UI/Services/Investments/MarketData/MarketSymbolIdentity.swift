import Foundation

struct MarketSymbolIdentity: Equatable, Sendable {
    let requestedSymbol: String
    let canonicalSymbol: String?
    let providerSymbol: String?
    let assetID: String?

    init(
        requestedSymbol: String,
        canonicalSymbol: String?,
        providerSymbol: String?,
        assetID: String?
    ) {
        self.requestedSymbol = requestedSymbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        self.canonicalSymbol = Self.normalized(canonicalSymbol)
        self.providerSymbol = Self.normalized(providerSymbol)
        self.assetID = assetID?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init?(investment: Investment) {
        let requested = Self.requestedSymbol(
            marketSymbol: investment.marketSymbol,
            exchange: investment.marketExchange,
            quoteLookupKey: investment.marketQuoteLookupKey
        )
        guard let requested else { return nil }

        self.init(
            requestedSymbol: requested,
            canonicalSymbol: investment.marketQuoteLookupKey,
            providerSymbol: nil,
            assetID: investment.assetID
        )
    }

    init?(
        marketSymbol: String?,
        exchange: String?,
        quoteLookupKey: String?,
        assetID: String? = nil
    ) {
        let requested = Self.requestedSymbol(
            marketSymbol: marketSymbol,
            exchange: exchange,
            quoteLookupKey: quoteLookupKey
        )
        guard let requested else { return nil }

        self.init(
            requestedSymbol: requested,
            canonicalSymbol: quoteLookupKey,
            providerSymbol: nil,
            assetID: assetID
        )
    }

    func updating(with quote: AssetSummary) -> MarketSymbolIdentity {
        MarketSymbolIdentity(
            requestedSymbol: requestedSymbol,
            canonicalSymbol: quote.canonicalQuoteLookupKey,
            providerSymbol: quote.providerSymbol,
            assetID: assetID
        )
    }

    private static func requestedSymbol(
        marketSymbol: String?,
        exchange: String?,
        quoteLookupKey: String?
    ) -> String? {
        if let lookupKey = normalized(quoteLookupKey), !lookupKey.isEmpty {
            return lookupKey
        }

        if let symbol = normalized(marketSymbol), !symbol.isEmpty {
            let canonical = MarketInstrumentIdentity.canonicalQuoteLookupKey(
                symbol: symbol,
                exchange: exchange
            )
            return canonical.isEmpty ? symbol : canonical
        }

        return nil
    }

    private static func normalized(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }
}
