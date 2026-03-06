//
//  BackupMetadata.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

struct BackupSchemaVersion: Comparable, Codable {
    let major: Int
    let minor: Int

    static let current = BackupSchemaVersion(major: 2, minor: 0)

    init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    init?(string: String) {
        let components = string.split(separator: ".").compactMap { Int($0) }
        guard components.count == 2 else { return nil }
        self.major = components[0]
        self.minor = components[1]
    }

    var stringValue: String {
        "\(major).\(minor)"
    }

    func isCompatible(with current: BackupSchemaVersion) -> Bool {
        major == current.major
    }

    static func < (lhs: BackupSchemaVersion, rhs: BackupSchemaVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        return lhs.minor < rhs.minor
    }
}

struct BackupMetadata: Codable {
    static let currentSchema = BackupSchemaVersion.current
    static let currentSchemaVersion = currentSchema.stringValue
    
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

    var parsedSchemaVersion: BackupSchemaVersion? {
        BackupSchemaVersion(string: schemaVersion)
    }

    func isCompatibleWithCurrentSchema() -> Bool {
        guard let parsedSchemaVersion else { return false }
        return parsedSchemaVersion.isCompatible(with: Self.currentSchema)
    }
}
