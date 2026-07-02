import Foundation
import SwiftData

@Model
final class AccountDailySnapshot: Persistable {
    var accountID: String = ""
    var dateKey: String = ""
    var accountBalance: Double = 0
    var accountCurrency: String = "RUB"
    var baseCurrency: String = "RUB"
    var fxRateToBase: Double = 1
    var balanceInBaseCurrency: Double = 0
    var rateProvider: String = "unknown"
    var rateTimestamp: Date = Date()
    var snapshotState: String = DailySnapshotState.open.rawValue
    var timezoneIdentifier: String = TimeZone.current.identifier
    var closedAt: Date?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    var state: DailySnapshotState {
        get { DailySnapshotState(rawValue: snapshotState) ?? .open }
        set { snapshotState = newValue.rawValue }
    }

    init(
        accountID: String,
        dateKey: String,
        accountBalance: Double,
        accountCurrency: String,
        baseCurrency: String,
        fxRateToBase: Double,
        balanceInBaseCurrency: Double,
        rateProvider: String,
        rateTimestamp: Date = Date(),
        snapshotState: DailySnapshotState,
        timezoneIdentifier: String = TimeZone.current.identifier,
        closedAt: Date?,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.accountID = accountID
        self.dateKey = dateKey
        self.accountBalance = accountBalance
        self.accountCurrency = accountCurrency
        self.baseCurrency = baseCurrency
        self.fxRateToBase = fxRateToBase
        self.balanceInBaseCurrency = balanceInBaseCurrency
        self.rateProvider = rateProvider
        self.rateTimestamp = rateTimestamp
        self.snapshotState = snapshotState.rawValue
        self.timezoneIdentifier = timezoneIdentifier
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "AccountDailySnapshot",
            "accountID": accountID,
            "dateKey": dateKey,
            "accountBalance": accountBalance,
            "accountCurrency": accountCurrency,
            "baseCurrency": baseCurrency,
            "fxRateToBase": fxRateToBase,
            "balanceInBaseCurrency": balanceInBaseCurrency,
            "rateProvider": rateProvider,
            "rateTimestamp": rateTimestamp.timeIntervalSince1970,
            "snapshotState": snapshotState,
            "timezoneIdentifier": timezoneIdentifier,
            "createdAt": createdAt.timeIntervalSince1970,
            "updatedAt": updatedAt.timeIntervalSince1970
        ].merging(closedAt.map { ["closedAt": $0.timeIntervalSince1970] } ?? [:]) { current, _ in current }
        return try JSONSerialization.data(withJSONObject: dict)
    }

    static func `import`(_ data: Data) throws {
        guard let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              canImport(from: dict) else {
            throw AppError.backupCorrupted
        }
    }

    static func canImport(from dict: [String: Any]) -> Bool {
        dict["type"] as? String == "AccountDailySnapshot" &&
        dict["accountID"] as? String != nil &&
        dict["dateKey"] as? String != nil
    }
}

struct AccountDailySnapshotImporter: ModelImporter {
    static func importType() -> String { "AccountDailySnapshot" }
    static var importPriority: Int { 30 }

    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let accountID = dict["accountID"] as? String,
              let dateKey = dict["dateKey"] as? String,
              let accountBalance = dict["accountBalance"] as? Double,
              let accountCurrency = dict["accountCurrency"] as? String,
              let baseCurrency = dict["baseCurrency"] as? String,
              let fxRateToBase = dict["fxRateToBase"] as? Double,
              let balanceInBaseCurrency = dict["balanceInBaseCurrency"] as? Double,
              let rateProvider = dict["rateProvider"] as? String,
              let snapshotStateRaw = dict["snapshotState"] as? String,
              let snapshotState = DailySnapshotState(rawValue: snapshotStateRaw) else {
            throw AppError.backupCorrupted
        }

        let existing = try AccountDailySnapshotReader.fetchAccountSnapshot(
            context: context,
            accountID: accountID,
            dateKey: dateKey,
            baseCurrency: baseCurrency
        )
        if existing != nil { return }

        let snapshot = AccountDailySnapshot(
            accountID: accountID,
            dateKey: dateKey,
            accountBalance: accountBalance,
            accountCurrency: accountCurrency,
            baseCurrency: baseCurrency,
            fxRateToBase: fxRateToBase,
            balanceInBaseCurrency: balanceInBaseCurrency,
            rateProvider: rateProvider,
            rateTimestamp: Date(timeIntervalSince1970: dict["rateTimestamp"] as? TimeInterval ?? Date().timeIntervalSince1970),
            snapshotState: snapshotState,
            timezoneIdentifier: dict["timezoneIdentifier"] as? String ?? TimeZone.current.identifier,
            closedAt: (dict["closedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
            createdAt: Date(timeIntervalSince1970: dict["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970),
            updatedAt: Date(timeIntervalSince1970: dict["updatedAt"] as? TimeInterval ?? Date().timeIntervalSince1970)
        )
        context.insert(snapshot)
    }
}

