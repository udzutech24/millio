import Foundation
import SwiftData

struct DailySnapshotAmountPoint: Equatable {
    let dateKey: String
    let date: Date
    let amount: Double
    let state: DailySnapshotState
}

enum AccountDailySnapshotReader {
    private struct AccountSnapshotKey: Hashable {
        let accountID: String
        let dateKey: String
    }

    static func dateKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(from dateKey: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateKey)
    }

    static func fetchAccountSnapshot(
        context: ModelContext,
        accountID: String,
        dateKey: String,
        baseCurrency: String
    ) throws -> AccountDailySnapshot? {
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == accountID &&
                snapshot.dateKey == dateKey &&
                snapshot.baseCurrency == baseCurrency
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    static func fetchPortfolioSnapshot(
        context: ModelContext,
        dateKey: String,
        baseCurrency: String
    ) throws -> PortfolioDailySnapshot? {
        let descriptor = FetchDescriptor<PortfolioDailySnapshot>(
            predicate: #Predicate<PortfolioDailySnapshot> { snapshot in
                snapshot.dateKey == dateKey &&
                snapshot.baseCurrency == baseCurrency
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).first
    }

    static func accountDailyAmounts(
        context: ModelContext,
        accountID: String,
        currency: String,
        daysCount: Int,
        referenceDate: Date = Date()
    ) -> [Double?] {
        let start = Calendar.current.startOfDay(for: referenceDate)
        let keys = (0..<daysCount).reversed().compactMap { offset -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return dateKey(for: date)
        }
        guard !keys.isEmpty else { return [] }

        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == accountID &&
                snapshot.accountCurrency == currency
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []
        let byKey = latestAccountSnapshotsByDate(snapshots).mapValues(\.accountBalance)
        return keys.map { byKey[$0] }
    }

    static func portfolioDailyAmounts(
        context: ModelContext,
        currency: String,
        daysCount: Int,
        referenceDate: Date = Date()
    ) -> [Double?] {
        let start = Calendar.current.startOfDay(for: referenceDate)
        let keys = (0..<daysCount).reversed().compactMap { offset -> String? in
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: start) else { return nil }
            return dateKey(for: date)
        }
        guard !keys.isEmpty else { return [] }

        let descriptor = FetchDescriptor<PortfolioDailySnapshot>(
            predicate: #Predicate<PortfolioDailySnapshot> { snapshot in
                snapshot.baseCurrency == currency
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )
        let snapshots = (try? context.fetch(descriptor)) ?? []
        let byKey = latestPortfolioSnapshotsByDate(snapshots).mapValues(\.totalBalanceInBaseCurrency)
        return keys.map { byKey[$0] }
    }

    static func accountPortfolioDailyAmounts(
        context: ModelContext,
        accountIDs: [String],
        baseCurrency: String,
        daysCount: Int,
        referenceDate: Date = Date()
    ) -> [Double?] {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: referenceDate)
        let dates = (0..<daysCount).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: start)
        }
        guard let first = dates.first, let last = dates.last else { return [] }

        let points = accountPortfolioDailyPoints(
            context: context,
            accountIDs: accountIDs,
            baseCurrency: baseCurrency,
            startDate: first,
            endDate: last,
            requireEveryClosedDay: false
        )
        let byKey = Dictionary(uniqueKeysWithValues: points.map { ($0.dateKey, $0.amount) })
        return dates.map { byKey[dateKey(for: $0)] }
    }

    static func contiguousKnownAmounts(from amounts: [Double?]) -> [Double] {
        guard let first = amounts.firstIndex(where: { $0 != nil }),
              let last = amounts.lastIndex(where: { $0 != nil }),
              first <= last else {
            return []
        }

        let knownWindow = amounts[first...last]
        guard knownWindow.allSatisfy({ $0 != nil }) else { return [] }
        return knownWindow.compactMap { $0 }
    }

    static func portfolioDailyPoints(
        context: ModelContext,
        currency: String,
        startDate: Date,
        endDate: Date
    ) -> [DailySnapshotAmountPoint] {
        let startKey = dateKey(for: Calendar.current.startOfDay(for: startDate))
        let endKey = dateKey(for: Calendar.current.startOfDay(for: endDate))
        let descriptor = FetchDescriptor<PortfolioDailySnapshot>(
            predicate: #Predicate<PortfolioDailySnapshot> { snapshot in
                snapshot.baseCurrency == currency &&
                snapshot.dateKey >= startKey &&
                snapshot.dateKey <= endKey
            },
            sortBy: [SortDescriptor(\.dateKey)]
        )
        let snapshots = latestPortfolioSnapshotsByDate((try? context.fetch(descriptor)) ?? [])
        return snapshots.values
            .compactMap { snapshot -> DailySnapshotAmountPoint? in
                guard let date = date(from: snapshot.dateKey) else { return nil }
                return DailySnapshotAmountPoint(
                    dateKey: snapshot.dateKey,
                    date: date,
                    amount: snapshot.totalBalanceInBaseCurrency,
                    state: snapshot.state
                )
            }
            .sorted { $0.date < $1.date }
    }

    static func accountPortfolioDailyPoints(
        context: ModelContext,
        accountIDs: [String],
        baseCurrency: String,
        startDate: Date,
        endDate: Date,
        requiredAccountIDsByDateKey: ((String, Date) -> [String])? = nil,
        requireEveryClosedDay: Bool = true
    ) -> [DailySnapshotAmountPoint] {
        let uniqueAccountIDs = Array(Set(accountIDs)).sorted()
        guard !uniqueAccountIDs.isEmpty else { return [] }

        let calendar = Calendar.current
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        guard startDay <= endDay else { return [] }

        let startKey = dateKey(for: startDay)
        let endKey = dateKey(for: endDay)
        let accountIDSet = Set(uniqueAccountIDs)
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.baseCurrency == baseCurrency &&
                snapshot.dateKey >= startKey &&
                snapshot.dateKey <= endKey
            },
            sortBy: [
                SortDescriptor(\.dateKey),
                SortDescriptor(\.accountID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let snapshots = ((try? context.fetch(descriptor)) ?? [])
            .filter { accountIDSet.contains($0.accountID) }

        let latestByAccountAndDay = latestAccountSnapshotsByAccountAndDate(snapshots)
        var points: [DailySnapshotAmountPoint] = []
        var day = startDay

        while day <= endDay {
            let key = dateKey(for: day)
            let requiredAccountIDs = requiredAccountIDsByDateKey?(key, day) ?? uniqueAccountIDs
            if requiredAccountIDs.isEmpty {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
                continue
            }

            var total = 0.0
            var states: [DailySnapshotState] = []

            for accountID in requiredAccountIDs {
                guard let snapshot = latestByAccountAndDay[AccountSnapshotKey(accountID: accountID, dateKey: key)],
                      let state = DailySnapshotState(rawValue: snapshot.snapshotState),
                      state.isFullyClosed else {
                    if requireEveryClosedDay {
                        return []
                    }
                    total = .nan
                    break
                }
                total += snapshot.balanceInBaseCurrency
                states.append(state)
            }

            if !total.isNaN {
                points.append(DailySnapshotAmountPoint(
                    dateKey: key,
                    date: day,
                    amount: total,
                    state: aggregateState(from: states)
                ))
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        return points
    }

    static func accountRecordCount(context: ModelContext, accountID: String, currency: String) -> Int {
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.accountID == accountID &&
                snapshot.accountCurrency == currency
            }
        )
        return ((try? context.fetch(descriptor)) ?? []).count
    }

    private static func latestAccountSnapshotsByDate(_ snapshots: [AccountDailySnapshot]) -> [String: AccountDailySnapshot] {
        snapshots.reduce(into: [:]) { result, snapshot in
            if let existing = result[snapshot.dateKey], existing.updatedAt >= snapshot.updatedAt {
                return
            }
            result[snapshot.dateKey] = snapshot
        }
    }

    private static func latestAccountSnapshotsByAccountAndDate(_ snapshots: [AccountDailySnapshot]) -> [AccountSnapshotKey: AccountDailySnapshot] {
        snapshots.reduce(into: [:]) { result, snapshot in
            let key = AccountSnapshotKey(accountID: snapshot.accountID, dateKey: snapshot.dateKey)
            if let existing = result[key], existing.updatedAt >= snapshot.updatedAt {
                return
            }
            result[key] = snapshot
        }
    }

    static func latestClosedAccountSnapshotsByAccount(
        context: ModelContext,
        dateKey: String,
        baseCurrency: String
    ) throws -> [String: AccountDailySnapshot] {
        let descriptor = FetchDescriptor<AccountDailySnapshot>(
            predicate: #Predicate<AccountDailySnapshot> { snapshot in
                snapshot.dateKey == dateKey &&
                snapshot.baseCurrency == baseCurrency
            },
            sortBy: [
                SortDescriptor(\.accountID),
                SortDescriptor(\.updatedAt, order: .reverse)
            ]
        )
        let latest = latestAccountSnapshotsByAccountAndDate(try context.fetch(descriptor))
        return latest.values.reduce(into: [:]) { result, snapshot in
            guard DailySnapshotState(rawValue: snapshot.snapshotState)?.isFullyClosed == true else { return }
            result[snapshot.accountID] = snapshot
        }
    }

    private static func aggregateState(from states: [DailySnapshotState]) -> DailySnapshotState {
        states.contains(.fallbackClosed) ? .fallbackClosed : .closed
    }

    private static func latestPortfolioSnapshotsByDate(_ snapshots: [PortfolioDailySnapshot]) -> [String: PortfolioDailySnapshot] {
        snapshots.reduce(into: [:]) { result, snapshot in
            if let existing = result[snapshot.dateKey], existing.updatedAt >= snapshot.updatedAt {
                return
            }
            result[snapshot.dateKey] = snapshot
        }
    }
}
