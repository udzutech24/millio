import Foundation
import SwiftData

@MainActor
struct ProviderInstrumentResolver {
    let modelContext: ModelContext
    let providerName: String

    init(modelContext: ModelContext, providerName: String = MarketAssetIdentityResolver.defaultProviderName) {
        self.modelContext = modelContext
        self.providerName = providerName.lowercased()
    }

    func quoteLookupSymbols(for investment: Investment) -> [String] {
        let mappedSymbols = mappedQuoteLookupSymbols(for: investment)
        let legacySymbols = legacyQuoteLookupSymbols(for: investment)
        return uniqueQuoteSymbols(mappedSymbols + legacySymbols)
    }

    func preferredRefreshSymbol(for investment: Investment) -> String? {
        if let mapped = preferredMappedRefreshSymbol(for: investment) {
            return mapped
        }

        if let canonicalKey = normalizedCanonicalLookupKey(
            investment.marketQuoteLookupKey,
            exchange: investment.marketExchange
        ) {
            return canonicalKey
        }

        guard let rawSymbol = normalizedStoredValue(investment.marketSymbol) else {
            return nil
        }

        let canonicalKey = MarketInstrumentIdentity.canonicalQuoteLookupKey(
            symbol: rawSymbol,
            exchange: investment.marketExchange
        )
        return canonicalKey.isEmpty ? rawSymbol : canonicalKey
    }

    private func mappedQuoteLookupSymbols(for investment: Investment) -> [String] {
        guard let assetID = investment.assetID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !assetID.isEmpty else {
            return []
        }

        let mappings = fetchMappings(for: assetID)
        let preferredMappings = mappings.filter {
            $0.providerName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == providerName
        }
        let orderedMappings = preferredMappings.isEmpty ? mappings : preferredMappings

        return orderedMappings.flatMap { mapping in
            let providerSymbol = mapping.providerSymbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard let providerSymbol, !providerSymbol.isEmpty else { return [String]() }
            return uniqueQuoteSymbols(
                [providerSymbol] +
                MarketInstrumentIdentity.fallbackQuoteLookupKeys(
                    symbol: providerSymbol,
                    exchange: mapping.providerExchangeCode
                )
            )
        }
    }

    private func preferredMappedRefreshSymbol(for investment: Investment) -> String? {
        let rawSymbol = normalizedStoredValue(investment.marketSymbol)

        return mappedQuoteLookupSymbols(for: investment)
            .first { candidate in
                guard let rawSymbol else { return true }
                return candidate != rawSymbol
            }
    }

    private func legacyQuoteLookupSymbols(for investment: Investment) -> [String] {
        let canonicalKey = normalizedCanonicalLookupKey(
            investment.marketQuoteLookupKey,
            exchange: investment.marketExchange
        )
        let rawSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard !rawSymbol.isEmpty else {
            return canonicalKey.map { [$0] } ?? []
        }

        let primaryCanonicalKey = MarketInstrumentIdentity.canonicalQuoteLookupKey(
            symbol: rawSymbol,
            exchange: investment.marketExchange
        )
        let fallbacks = MarketInstrumentIdentity.fallbackQuoteLookupKeys(
            symbol: rawSymbol,
            exchange: investment.marketExchange
        )
        return uniqueQuoteSymbols(
            [canonicalKey, primaryCanonicalKey].compactMap { candidate in
                guard let candidate else { return nil }
                return candidate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            } + fallbacks
        )
    }

    private func normalizedCanonicalLookupKey(_ rawValue: String?, exchange: String?) -> String? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let normalized, !normalized.isEmpty else { return nil }

        let canonical = MarketInstrumentIdentity.canonicalQuoteLookupKey(
            symbol: normalized,
            exchange: exchange
        )
        return canonical.isEmpty ? normalized : canonical
    }

    private func normalizedStoredValue(_ rawValue: String?) -> String? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        guard let normalized, !normalized.isEmpty else { return nil }
        return normalized
    }

    private func fetchMappings(for assetID: String) -> [AssetProviderMapping] {
        let descriptor = FetchDescriptor<AssetProviderMapping>(
            predicate: #Predicate<AssetProviderMapping> { mapping in
                mapping.assetID == assetID
            }
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func uniqueQuoteSymbols(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { value in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !normalized.isEmpty else { return false }
            return seen.insert(normalized).inserted
        }
    }
}
