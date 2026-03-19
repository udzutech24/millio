//
//  SlideToConfirmHapticsPlanTests.swift
//  millioTests
//
//  Created by Codex on 11.03.2026.
//

import Testing
@testable import millio

struct SlideToConfirmHapticsPlanTests {
    @Test("Slide haptics progress step advances only after configured thresholds")
    func progressStepUsesThresholds() {
        #expect(SlideToConfirmHapticsPlan.progressStep(for: -0.1) == -1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0) == -1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.15) == -1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.16) == 0)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.4) == 1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.65) == 2)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.83) == 3)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 1.2) == 3)
    }

    @Test("Slide haptics completion matches action threshold")
    func completionThresholdMatchesActionThreshold() {
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: -0.5) == false)
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 0.85) == false)
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 0.86))
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 1.0))
    }

    @Test("Slide haptics escalate feedback toward completion")
    func feedbackEscalatesWithProgress() {
        let first = SlideToConfirmHapticsPlan.feedback(for: 0)
        let last = SlideToConfirmHapticsPlan.feedback(for: 3)

        #expect(first?.style == .soft)
        #expect(last?.style == .rigid)
        #expect((first?.intensity ?? 0) < (last?.intensity ?? 0))
        #expect(SlideToConfirmHapticsPlan.completionFeedback.primaryStyle == .heavy)
        #expect(SlideToConfirmHapticsPlan.completionFeedback.settleDelay > 0)
    }
}
