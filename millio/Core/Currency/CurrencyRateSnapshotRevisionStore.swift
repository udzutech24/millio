import Foundation

/// Идентичность полного набора текущих фиатных курсов.
///
/// Храним только метаданные, а не сами суммы: `RateRepository` остаётся владельцем matrix.
/// Revision позволяет display-cache понять, что он посчитан по другому набору курсов.
enum CurrencyRateSnapshotRevisionStore {
    private static let key = "currency_rate_snapshot_revision"

    static var current: String? {
        UserDefaults.standard.string(forKey: key)
    }

    static func revision(for snapshot: RateSnapshot) -> String {
        "\(snapshot.source.rawValue):\(snapshot.updatedAt):\(snapshot.fetchedAt)"
    }

    @discardableResult
    static func save(_ snapshot: RateSnapshot) -> String {
        let revision = revision(for: snapshot)
        UserDefaults.standard.set(revision, forKey: key)
        return revision
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
