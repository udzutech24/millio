import Foundation
import SwiftData

protocol PortfolioHeldSymbolsProviding: Sendable {
    @MainActor
    func heldSymbolsSnapshot() -> [String]
}

struct PortfolioHeldSymbolsSnapshotBuilder {
    /// Символы активных рыночных счетов нового ядра. Набор сознательно совпадает с тем, что
    /// опрашивает `AccountMarketPriceService.refreshTodayPrices()` — единый источник правды
    /// «какие символы отслеживаем» (иначе backend получал бы один список символов, а котировки
    /// тянулись бы по другому набору). Фильтра по количеству нет: в `MarketMeta` оно не хранится
    /// (выводится из событий), а любой активный рыночный счёт и так отслеживается прайс-сервисом.
    static func build(from accounts: [Account]) -> [String] {
        var uniqueSymbols = Set<String>()
        var orderedSymbols: [String] = []

        for account in accounts {
            guard account.kind == .marketInvestment, account.archivedAt == nil else { continue }
            guard let symbol = account.marketMeta?.symbol else { continue }

            let normalizedSymbol = symbol
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
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
        let descriptor = FetchDescriptor<Account>()
        let accounts = (try? modelContext.fetch(descriptor)) ?? []
        return PortfolioHeldSymbolsSnapshotBuilder.build(from: accounts)
    }
}
