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

    /// Ревизия строится по САМИМ значениям курсов, а не по времени загрузки.
    /// Иначе каждое фоновое обновление (новый `fetchedAt`) выглядело бы как новый набор курсов
    /// и заставляло UI пересчитываться и мигать, хотя цифры не изменились.
    /// Хэш детерминированный (FNV-1a), а не `Hasher` — тот засеян случайно на каждый запуск процесса
    /// и не пережил бы перезапуск приложения.
    static func revision(for snapshot: RateSnapshot) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        func combine(_ string: String) {
            for byte in string.utf8 {
                hash ^= UInt64(byte)
                hash = hash &* 0x100000001b3
            }
        }
        combine(snapshot.source.rawValue)
        for code in snapshot.rates.keys.sorted() {
            combine(code)
            // Округление до 10 знаков гасит дрожание double-представления одинаковых курсов.
            combine(String(format: "%.10f", snapshot.rates[code] ?? 0))
        }
        return "\(snapshot.source.rawValue):\(String(hash, radix: 16))"
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
