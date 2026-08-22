//
//  FinanceDynamicsSnapshotStore.swift
//  millio
//

import CryptoKit
import Foundation

/// Полный локальный результат общего экрана Analytics.
///
/// Это display-cache, а не источник финансовой истины: SwiftData остаётся единственным каноном,
/// а snapshot нужен только чтобы не показывать ложный пустой экран до завершения следующего расчёта.
struct FinanceDynamicsSnapshot: Codable, Equatable {
    struct Point: Codable, Equatable {
        let date: Date
        let value: Double
        let label: String
    }

    struct Breakdown: Codable, Equatable {
        let id: String
        let name: String
        let startValue: Double
        let endValue: Double
        let delta: Double
        let deltaPercent: Double?
        let icon: String?
        let isCreditCard: Bool
        let isArchived: Bool
    }

    struct CurrencyBreakdown: Codable, Equatable {
        let currency: String
        let convertedValue: Double
        let percentage: Double
    }

    let displayCurrency: String
    let periodRawValue: String
    let periodStartDate: Date
    let periodEndDate: Date
    let chartData: [Point]
    let currentBalance: Double
    let periodDeltaAbsolute: Double
    let periodDeltaPercent: Double?
    let dynamicsBreakdown: [Breakdown]
    let currencyBreakdown: [CurrencyBreakdown]
    /// Revision полного FX matrix, по которому посчитаны суммы.
    /// Старые cache-файлы без значения не восстанавливаются после введения общего snapshot.
    let rateSnapshotRevision: String?
    let savedAt: Date
}

protocol FinanceDynamicsSnapshotStoreProtocol: AnyObject {
    func load(scopeID: String) -> FinanceDynamicsSnapshot?
    func save(_ snapshot: FinanceDynamicsSnapshot, scopeID: String)
}

/// Scope-keyed snapshots are stored outside UserDefaults because they contain financial amounts.
/// `completeUntilFirstUserAuthentication` permits a fast resume after the owner unlocks the phone,
/// while iOS keeps the file unavailable before the first unlock after a reboot.
final class FinanceDynamicsSnapshotStore: FinanceDynamicsSnapshotStoreProtocol {
    private static let directoryName = "FinanceDynamicsSnapshots"
    private let fileManager: FileManager
    private let directoryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.directoryURL = directoryURL
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent(Self.directoryName, isDirectory: true)
    }

    func load(scopeID: String) -> FinanceDynamicsSnapshot? {
        guard let data = try? Data(contentsOf: fileURL(for: scopeID)) else { return nil }
        return try? decoder.decode(FinanceDynamicsSnapshot.self, from: data)
    }

    func save(_ snapshot: FinanceDynamicsSnapshot, scopeID: String) {
        guard let data = try? encoder.encode(snapshot) else { return }

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let url = fileURL(for: scopeID)
            try data.write(to: url, options: .atomic)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            // Cache is best-effort. Failure must never affect the canonical SwiftData data path.
        }
    }

    private func fileURL(for scopeID: String) -> URL {
        let digest = SHA256.hash(data: Data(scopeID.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(name).json", isDirectory: false)
    }
}
