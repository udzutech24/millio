//
//  SlideToConfirmHapticsPlan.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

/// Пороговая схема haptic-отклика для drag-слайдера подтверждения.
enum SlideToConfirmHapticsPlan {
    static let progressThresholds: [Double] = [0.2, 0.45, 0.7]
    static let completionThreshold: Double = 0.82

    static func progressStep(for progress: Double) -> Int {
        let normalized = min(max(progress, 0), 1)
        return progressThresholds.lastIndex(where: { normalized >= $0 }) ?? -1
    }

    static func isCompletionReached(for progress: Double) -> Bool {
        min(max(progress, 0), 1) >= completionThreshold
    }
}
