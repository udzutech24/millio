import Foundation
import SwiftData

protocol PortfolioHeldSymbolsProviding: Sendable {
    @MainActor
    func heldSymbolsSnapshot() -> [String]
}

struct PortfolioHeldSymbolsSnapshotBuilder {
    static func build(from investments: [Investment]) -> [String] {
        var uniqueSymbols = Set<String>()
        var orderedSymbols: [String] = []

        for investment in investments {
            guard investment.archivedAt == nil else { continue }
            guard investment.isMarketPriced else { continue }
            guard (investment.marketQuantity ?? 1) > 0 else { continue }

            let normalizedSymbol = investment.marketSymbol?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            guard !normalizedSymbol.isEmpty else { continue }

            if uniqueSymbols.insert(normalizedSymbol).inserted {
                orderedSymbols.append(normalizedSymbol)
            }
        }

        return orderedSymbols.sorted()
    }
}

@MainActor
final class InvestmentPortfolioHeldSymbolsProvider: PortfolioHeldSymbolsProviding {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func heldSymbolsSnapshot() -> [String] {
        let descriptor = FetchDescriptor<Investment>()
        let investments = (try? modelContext.fetch(descriptor)) ?? []
        return PortfolioHeldSymbolsSnapshotBuilder.build(from: investments)
    }
}
