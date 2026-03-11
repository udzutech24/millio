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
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.19) == -1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.2) == 0)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.5) == 1)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 0.7) == 2)
        #expect(SlideToConfirmHapticsPlan.progressStep(for: 1.2) == 2)
    }

    @Test("Slide haptics completion matches action threshold")
    func completionThresholdMatchesActionThreshold() {
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: -0.5) == false)
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 0.81) == false)
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 0.82))
        #expect(SlideToConfirmHapticsPlan.isCompletionReached(for: 1.0))
    }
}
