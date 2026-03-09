//
//  DebugMenuAccess.swift
//  millio
//
//  Created by Codex on 09.03.2026.
//

import CryptoKit
import Foundation

/// Policy + small utilities for gated access to the in-app debug menu.
enum DebugMenuAccessPolicy {
    static let unlockTapCount = 4
    static let unlockTapResetInterval: TimeInterval = 4.0

    // SHA-256("mil26") in hex to avoid storing the password in plain text.
    private static let requiredPasswordHashHex = "ca78a760b49216631721cc18d4449331223e4af029ef5f56295fbe2cc3563bbc"

    static func validate(password: String) -> Bool {
        let normalized = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }
        let digest = SHA256.hash(data: Data(normalized.utf8))
        return digest.hexString == requiredPasswordHashHex
    }
}

/// Detects a sequence of taps (N taps within a time window).
struct MultiTapGate: Equatable {
    let targetCount: Int
    let resetInterval: TimeInterval

    private(set) var tapCount: Int = 0
    private var lastTapAt: Date?

    init(targetCount: Int, resetInterval: TimeInterval) {
        precondition(targetCount > 0, "targetCount must be > 0")
        precondition(resetInterval >= 0, "resetInterval must be >= 0")
        self.targetCount = targetCount
        self.resetInterval = resetInterval
    }

    /// Returns `true` when the target tap count is reached.
    /// After triggering, the internal state resets.
    mutating func registerTap(at date: Date = Date()) -> Bool {
        if let lastTapAt, date.timeIntervalSince(lastTapAt) > resetInterval {
            tapCount = 0
        }

        tapCount += 1
        lastTapAt = date

        if tapCount >= targetCount {
            reset()
            return true
        }

        return false
    }

    mutating func reset() {
        tapCount = 0
        lastTapAt = nil
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
