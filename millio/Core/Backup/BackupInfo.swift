//
//  BackupInfo.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

struct BackupInfo: Codable, Equatable, Sendable {
    let date: Date
    let size: Int64
    let version: String

    var backupVersion: BackupVersion? {
        BackupVersion(string: version)
    }
}

// Откуда пришла запись в списке версий (только для диагностики, не хранится в CK).
enum BackupVersionSource: String, Sendable {
    case index          // из AppBackupIndex (кэш)
    case snapshotQuery  // прямой CKQuery по AppBackup records
    case legacyLatest   // запись latest_backup (старый формат)
    case unknown
}

struct BackupVersionInfo: Codable, Identifiable, Equatable, Sendable {
    let recordName: String
    let date: Date
    let size: Int64
    let version: String
    let isPinned: Bool
    // Диагностическое поле: не участвует в Codable и Equatable
    var source: BackupVersionSource = .unknown

    var id: String { recordName }

    init(recordName: String, date: Date, size: Int64, version: String, isPinned: Bool, source: BackupVersionSource = .unknown) {
        self.recordName = recordName
        self.date = date
        self.size = size
        self.version = version
        self.isPinned = isPinned
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case recordName, date, size, version, isPinned
    }

    static func == (lhs: BackupVersionInfo, rhs: BackupVersionInfo) -> Bool {
        lhs.recordName == rhs.recordName &&
        lhs.date == rhs.date &&
        lhs.size == rhs.size &&
        lhs.version == rhs.version &&
        lhs.isPinned == rhs.isPinned
    }
}
