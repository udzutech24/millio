import Foundation
import SwiftData

enum DailySnapshotMigrationError: Error {
    case importedCountMismatch(expectedAccount: Int, actualAccount: Int, expectedPortfolio: Int, actualPortfolio: Int)
}

@MainActor
enum DailySnapshotMigrator {
    private static let migrationKey = "daily_snapshot_migration_v1_completed"

    private struct AccountKey: Hashable {
        let accountID: String
        let dateKey: String
        let baseCurrency: String
    }

    private struct PortfolioKey: Hashable {
        let dateKey: String
        let baseCurrency: String
    }

    static func migrateIfNeeded(
        context: ModelContext,
        today: Date = Date(),
        scopeIdentifier: String = "default"
    ) throws {
        let scopedMigrationKey = migrationKey(for: scopeIdentifier)
        guard !UserDefaults.standard.bool(forKey: scopedMigrationKey) else { return }

        let todayKey = AccountDailySnapshotReader.dateKey(for: today)
        let now = Date()
        let accountSource = AccountBalanceHistoryStore.loadRaw()
        let portfolioSource = DashboardBalanceHistoryStore.loadRaw()

        var accountKeys = Set<AccountKey>()
        for (accountID, records) in accountSource {
            for record in records where record.dateKey < todayKey {
                let currency = normalizedCurrency(record.currency)
                let key = AccountKey(accountID: accountID, dateKey: record.dateKey, baseCurrency: currency)
                accountKeys.insert(key)

                if try AccountDailySnapshotReader.fetchAccountSnapshot(
                    context: context,
                    accountID: accountID,
                    dateKey: record.dateKey,
                    baseCurrency: currency
                ) != nil {
                    continue
                }

                context.insert(AccountDailySnapshot(
                    accountID: accountID,
                    dateKey: record.dateKey,
                    accountBalance: record.amount,
                    accountCurrency: currency,
                    baseCurrency: currency,
                    fxRateToBase: 1,
                    balanceInBaseCurrency: record.amount,
                    rateProvider: "fallback",
                    rateTimestamp: now,
                    snapshotState: .fallbackClosed,
                    timezoneIdentifier: TimeZone.current.identifier,
                    closedAt: now,
                    createdAt: now,
                    updatedAt: now
                ))
            }
        }

        var portfolioKeys = Set<PortfolioKey>()
        for record in portfolioSource where record.dateKey < todayKey {
            let currency = normalizedCurrency(record.currency)
            let key = PortfolioKey(dateKey: record.dateKey, baseCurrency: currency)
            portfolioKeys.insert(key)

            if try AccountDailySnapshotReader.fetchPortfolioSnapshot(
                context: context,
                dateKey: record.dateKey,
                baseCurrency: currency
            ) != nil {
                continue
            }

            context.insert(PortfolioDailySnapshot(
                dateKey: record.dateKey,
                totalBalanceInBaseCurrency: record.amount,
                baseCurrency: currency,
                snapshotState: .fallbackClosed,
                timezoneIdentifier: TimeZone.current.identifier,
                closedAt: now,
                createdAt: now,
                updatedAt: now
            ))
        }

        let actualAccount = try countAccountSnapshots(context: context, keys: accountKeys)
        let actualPortfolio = try countPortfolioSnapshots(context: context, keys: portfolioKeys)
        guard actualAccount == accountKeys.count, actualPortfolio == portfolioKeys.count else {
            throw DailySnapshotMigrationError.importedCountMismatch(
                expectedAccount: accountKeys.count,
                actualAccount: actualAccount,
                expectedPortfolio: portfolioKeys.count,
                actualPortfolio: actualPortfolio
            )
        }

        try context.save()
        AccountBalanceHistoryStore.renameToMigrated()
        DashboardBalanceHistoryStore.clearUserDefaults()
        UserDefaults.standard.set(true, forKey: scopedMigrationKey)
    }

    static func migrationKey(for scopeIdentifier: String) -> String {
        let trimmed = scopeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "default" else { return migrationKey }
        return "\(migrationKey).\(trimmed)"
    }

    private static func countAccountSnapshots(context: ModelContext, keys: Set<AccountKey>) throws -> Int {
        guard !keys.isEmpty else { return 0 }
        let snapshots = try context.fetch(FetchDescriptor<AccountDailySnapshot>())
        return snapshots.reduce(0) { count, snapshot in
            let key = AccountKey(
                accountID: snapshot.accountID,
                dateKey: snapshot.dateKey,
                baseCurrency: snapshot.baseCurrency
            )
            return count + (keys.contains(key) ? 1 : 0)
        }
    }

    private static func countPortfolioSnapshots(context: ModelContext, keys: Set<PortfolioKey>) throws -> Int {
        guard !keys.isEmpty else { return 0 }
        let snapshots = try context.fetch(FetchDescriptor<PortfolioDailySnapshot>())
        return snapshots.reduce(0) { count, snapshot in
            let key = PortfolioKey(dateKey: snapshot.dateKey, baseCurrency: snapshot.baseCurrency)
            return count + (keys.contains(key) ? 1 : 0)
        }
    }

    private static func normalizedCurrency(_ currency: String) -> String {
        let trimmed = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? SettingsManager.shared.primaryCurrencyCode : trimmed
    }
}
