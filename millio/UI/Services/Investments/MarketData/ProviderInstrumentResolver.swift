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

    private func legacyQuoteLookupSymbols(for investment: Investment) -> [String] {
        let canonicalKey = investment.marketQuoteLookupKey?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        let rawSymbol = investment.marketSymbol?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
        guard !rawSymbol.isEmpty else {
            return canonicalKey.map { [$0] } ?? []
        }

        let fallbacks = MarketInstrumentIdentity.fallbackQuoteLookupKeys(
            symbol: rawSymbol,
            exchange: investment.marketExchange
        )
        return uniqueQuoteSymbols(([canonicalKey].compactMap { $0 }) + fallbacks)
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
