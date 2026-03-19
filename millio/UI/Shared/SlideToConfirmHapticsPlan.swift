//
//  SlideToConfirmHapticsPlan.swift
//  millio
//
//  Created by Codex on 11.03.2026.
//

/// Пороговая схема haptic-отклика для drag-слайдера подтверждения.
/// Делает свайп более "собранным": мягкий старт, затем усиление и двойное завершение.
enum SlideToConfirmHapticsPlan {
    enum ImpactStyle: Equatable {
        case soft
        case light
        case medium
        case rigid
        case heavy
    }

    struct ProgressFeedback: Equatable {
        let step: Int
        let style: ImpactStyle
        let intensity: Double
    }

    struct CompletionFeedback: Equatable {
        let primaryStyle: ImpactStyle
        let primaryIntensity: Double
        let settleStyle: ImpactStyle
        let settleIntensity: Double
        let settleDelay: Double
    }

    static let progressThresholds: [Double] = [0.16, 0.38, 0.62, 0.8]
    static let completionThreshold: Double = 0.86
    static let progressFeedback: [ProgressFeedback] = [
        ProgressFeedback(step: 0, style: .soft, intensity: 0.38),
        ProgressFeedback(step: 1, style: .light, intensity: 0.52),
        ProgressFeedback(step: 2, style: .medium, intensity: 0.7),
        ProgressFeedback(step: 3, style: .rigid, intensity: 0.92)
    ]
    static let completionFeedback = CompletionFeedback(
        primaryStyle: .heavy,
        primaryIntensity: 1.0,
        settleStyle: .soft,
        settleIntensity: 0.46,
        settleDelay: 0.06
    )

    static func progressStep(for progress: Double) -> Int {
        let normalized = min(max(progress, 0), 1)
        return progressThresholds.lastIndex(where: { normalized >= $0 }) ?? -1
    }

    static func feedback(for step: Int) -> ProgressFeedback? {
        progressFeedback.first(where: { $0.step == step })
    }

    static func isCompletionReached(for progress: Double) -> Bool {
        min(max(progress, 0), 1) >= completionThreshold
    }
}
