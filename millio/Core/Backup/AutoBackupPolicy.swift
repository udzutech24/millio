//
//  AutoBackupPolicy.swift
//  millio
//
//  Created by Codex on 12.03.2026.
//

import Foundation

struct AutoBackupPolicy {
    static let everyThreeDays = AutoBackupPolicy(minimumInterval: 3 * 24 * 60 * 60)

    let minimumInterval: TimeInterval

    func shouldRun(lastBackupDate: Date?, now: Date) -> Bool {
        guard let lastBackupDate else {
            return true
        }
        return now.timeIntervalSince(lastBackupDate) >= minimumInterval
    }
}
