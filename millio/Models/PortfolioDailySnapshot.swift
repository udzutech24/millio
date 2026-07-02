import Foundation
import SwiftData

@Model
final class PortfolioDailySnapshot: Persistable {
    var dateKey: String = ""
    var totalBalanceInBaseCurrency: Double = 0
    var baseCurrency: String = "RUB"
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
        dateKey: String,
        totalBalanceInBaseCurrency: Double,
        baseCurrency: String,
        snapshotState: DailySnapshotState,
        timezoneIdentifier: String = TimeZone.current.identifier,
        closedAt: Date?,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.dateKey = dateKey
        self.totalBalanceInBaseCurrency = totalBalanceInBaseCurrency
        self.baseCurrency = baseCurrency
        self.snapshotState = snapshotState.rawValue
        self.timezoneIdentifier = timezoneIdentifier
        self.closedAt = closedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func export() throws -> Data {
        let dict: [String: Any] = [
            "type": "PortfolioDailySnapshot",
            "dateKey": dateKey,
            "totalBalanceInBaseCurrency": totalBalanceInBaseCurrency,
            "baseCurrency": baseCurrency,
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
        dict["type"] as? String == "PortfolioDailySnapshot" &&
        dict["dateKey"] as? String != nil
    }
}

struct PortfolioDailySnapshotImporter: ModelImporter {
    static func importType() -> String { "PortfolioDailySnapshot" }
    static var importPriority: Int { 31 }

    static func `import`(from dict: [String: Any], context: ModelContext) throws {
        guard let dateKey = dict["dateKey"] as? String,
              let total = dict["totalBalanceInBaseCurrency"] as? Double,
              let baseCurrency = dict["baseCurrency"] as? String,
              let snapshotStateRaw = dict["snapshotState"] as? String,
              let snapshotState = DailySnapshotState(rawValue: snapshotStateRaw) else {
            throw AppError.backupCorrupted
        }

        let existing = try AccountDailySnapshotReader.fetchPortfolioSnapshot(
            context: context,
            dateKey: dateKey,
            baseCurrency: baseCurrency
        )
        if existing != nil { return }

        let snapshot = PortfolioDailySnapshot(
            dateKey: dateKey,
            totalBalanceInBaseCurrency: total,
            baseCurrency: baseCurrency,
            snapshotState: snapshotState,
            timezoneIdentifier: dict["timezoneIdentifier"] as? String ?? TimeZone.current.identifier,
            closedAt: (dict["closedAt"] as? TimeInterval).map(Date.init(timeIntervalSince1970:)),
            createdAt: Date(timeIntervalSince1970: dict["createdAt"] as? TimeInterval ?? Date().timeIntervalSince1970),
            updatedAt: Date(timeIntervalSince1970: dict["updatedAt"] as? TimeInterval ?? Date().timeIntervalSince1970)
        )
        context.insert(snapshot)
    }
}

