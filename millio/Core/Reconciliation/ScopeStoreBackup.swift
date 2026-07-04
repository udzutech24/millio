import Foundation

/// Автобэкап store-файлов ДО первой записи merge (Track B, митигация B1b №7).
/// copy (не move) — оба стора должны остаться рабочими (спека §4). Суффикс `.premerge.bak`.
enum ScopeStoreBackup {
    private static let suffix = ".premerge.bak"
    /// SQLite WAL/SHM — без них восстановление из .store может потерять незакоммиченные страницы.
    private static let sidecars = ["", "-wal", "-shm"]

    /// Копирует `.store` (+ `-wal`, `-shm`) каждого переданного стора в `*.premerge.bak`.
    /// Best-effort: ошибки копирования не срывают merge (бэкап — подстраховка, не критпуть), но логируются.
    static func backup(storeURLs: [URL]) {
        for storeURL in storeURLs {
            for sidecar in sidecars {
                let source = URL(fileURLWithPath: storeURL.path + sidecar)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                let destination = URL(fileURLWithPath: storeURL.path + sidecar + suffix)
                do {
                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.copyItem(at: source, to: destination)
                } catch {
                    AppLogger.log(.error, category: "Reconciliation",
                                  "premerge.bak copy failed for \(source.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }
    }
}
