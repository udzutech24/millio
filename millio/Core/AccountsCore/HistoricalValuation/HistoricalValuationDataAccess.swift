import Foundation
import SwiftData

/// Typed SwiftData/cache seam for the new structured valuation boundary. The legacy numeric
/// reader remains untouched until cutover, while every operation used by the new boundary throws.
@MainActor
struct HistoricalValuationDataAccess {
    let fetchAccounts: @MainActor () throws -> [Account]
    let makeMarketPriceProvider: @MainActor ([Account]) throws -> MarketPriceProviding?
    let rebuildSnapshots: @MainActor (Account, Date, MarketPriceProviding?) async throws -> Void
    let fetchLatestSnapshot: @MainActor (Account, String) throws -> AccountDailySnapshot?
    let fetchEvents: @MainActor (Account) throws -> [AccountEvent]

    static func live(
        modelContext: ModelContext,
        rebuilder: AccountSnapshotRebuilder,
        marketPriceService: AccountMarketPriceService?
    ) -> Self {
        Self(
            fetchAccounts: {
                try modelContext.fetch(FetchDescriptor<Account>())
            },
            makeMarketPriceProvider: { accounts in
                guard let marketPriceService else { return nil }
                let symbols = accounts.compactMap {
                    $0.kind == .marketInvestment ? $0.marketMeta?.symbol : nil
                }
                guard !symbols.isEmpty else { return nil }
                return marketPriceService.makeSnapshotProvider(symbols: symbols)
            },
            rebuildSnapshots: { account, date, priceProvider in
                try await rebuilder.rebuild(
                    accountID: account.persistentModelID,
                    upTo: date,
                    priceProvider: priceProvider
                )
            },
            fetchLatestSnapshot: { account, dayKey in
                let accountID = account.id
                var descriptor = FetchDescriptor<AccountDailySnapshot>(
                    predicate: #Predicate<AccountDailySnapshot> {
                        $0.account?.id == accountID && $0.dayKey <= dayKey
                    }
                )
                descriptor.sortBy = [SortDescriptor(\.dayKey, order: .reverse)]
                descriptor.fetchLimit = 1
                return try modelContext.fetch(descriptor).first
            },
            fetchEvents: { account in
                let accountID = account.id
                return try modelContext.fetch(
                    FetchDescriptor<AccountEvent>(
                        predicate: #Predicate<AccountEvent> { $0.account?.id == accountID }
                    )
                )
            }
        )
    }
}
