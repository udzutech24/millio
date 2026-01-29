//
//  BackupMetadata.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

struct BackupMetadata: Codable {
    let version: BackupVersion
    let timestamp: Date
    let schemaVersion: String
    let modelCount: Int
    
    init(
        version: BackupVersion = .current,
        timestamp: Date = Date(),
        schemaVersion: String = "2.0",
        modelCount: Int = 0
    ) {
        self.version = version
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.modelCount = modelCount
    }
}
