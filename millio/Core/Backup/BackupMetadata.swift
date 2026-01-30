//
//  BackupMetadata.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

struct BackupMetadata: Codable {
    static let currentSchemaVersion = "2.0"
    
    let version: BackupVersion
    let timestamp: Date
    let schemaVersion: String
    let modelCount: Int
    
    init(
        version: BackupVersion = .current,
        timestamp: Date = Date(),
        schemaVersion: String = BackupMetadata.currentSchemaVersion,
        modelCount: Int = 0
    ) {
        self.version = version
        self.timestamp = timestamp
        self.schemaVersion = schemaVersion
        self.modelCount = modelCount
    }
}
