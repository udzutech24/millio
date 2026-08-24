//
//  FinanceDynamicsSnapshotStore.swift
//  millio
//

import CryptoKit
import Foundation

/// Последний посчитанный результат общего экрана «Динамика».
///
/// Это display-cache, а не источник финансовой истины: SwiftData остаётся единственным каноном,
/// snapshot нужен только чтобы на холодном старте не показывать ложный пустой экран
/// («0 ₽» / «Нет данных» / «Нет групп») до завершения первого локального расчёта.
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
    /// Ревизия полного набора курсов, по которому посчитаны суммы
    /// (`CurrencyRateSnapshotRevisionStore.revision(for:)`, считается по значениям курсов).
    /// `nil` = курсы на момент расчёта неизвестны; тогда кэш восстанавливается только при
    /// таком же неизвестном наборе.
    let rateSnapshotRevision: String?
    let savedAt: Date
}

/// Долговременное хранилище display-cache экрана «Динамика», разделённое по data scope.
protocol FinanceDynamicsSnapshotStoreProtocol: AnyObject {
    func load(scopeID: String) -> FinanceDynamicsSnapshot?
    func save(_ snapshot: FinanceDynamicsSnapshot, scopeID: String)
}

/// Снимки лежат в файлах, а не в UserDefaults: они содержат финансовые суммы.
/// `completeUntilFirstUserAuthentication` позволяет быстро восстановить экран после
/// разблокировки телефона, но держит файл недоступным до первой разблокировки после перезагрузки.
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
            // Кэш — best-effort. Его сбой не должен влиять на канонический путь данных SwiftData.
        }
    }

    /// Имя файла — хэш scopeID: сам идентификатор может содержать user id, в имени файла его быть не должно.
    private func fileURL(for scopeID: String) -> URL {
        let digest = SHA256.hash(data: Data(scopeID.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directoryURL.appendingPathComponent("\(name).json", isDirectory: false)
    }
}
