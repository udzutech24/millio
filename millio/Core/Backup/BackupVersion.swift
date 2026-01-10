//
//  BackupVersion.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import Foundation

nonisolated struct BackupVersion: Comparable, Codable {
    let major: Int
    let minor: Int
    let patch: Int
    
    nonisolated static let current = BackupVersion(
        major: 1,
        minor: 0,
        patch: 0
    )
    
    nonisolated init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }
    
    nonisolated init?(string: String) {
        let components = string.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return nil }
        self.major = components[0]
        self.minor = components[1]
        self.patch = components[2]
    }
    
    nonisolated var stringValue: String {
        "\(major).\(minor).\(patch)"
    }
    
    nonisolated static func < (lhs: BackupVersion, rhs: BackupVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }
    
    /// Проверяет совместимость версий backup
    nonisolated func isCompatible(with current: BackupVersion) -> Bool {
        // Только major версия должна совпадать для совместимости
        return self.major == current.major
    }
}
