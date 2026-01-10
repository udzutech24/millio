//
//  BackupInfo.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

nonisolated struct BackupInfo: Codable {
    let date: Date
    let size: Int64
    let version: String
    
    nonisolated var backupVersion: BackupVersion? {
        BackupVersion(string: version)
    }
}
