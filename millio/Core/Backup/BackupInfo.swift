//
//  BackupInfo.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

struct BackupInfo: Codable, Equatable {
    let date: Date
    let size: Int64
    let version: String
    
    var backupVersion: BackupVersion? {
        BackupVersion(string: version)
    }
}

struct BackupVersionInfo: Codable, Identifiable, Equatable {
    let recordName: String
    let date: Date
    let size: Int64
    let version: String
    let isPinned: Bool

    var id: String { recordName }
}
