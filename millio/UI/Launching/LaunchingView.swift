//
//  LaunchingView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI
import UIKit
import AudioToolbox

struct LaunchingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var didStartAnimation = false
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkScale: CGFloat = 0.92
    @State private var progressOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            FinancialRainView()

            VStack(spacing: 28) {
                BrandWordmarkView()
                    .scaleEffect(wordmarkScale)
                    .opacity(wordmarkOpacity)

                ProgressView()
                    .tint(AppColors.textPrimary)
                    .scaleEffect(1.15)
                    .opacity(progressOpacity)
            }
        }
        .task {
            await startAnimationIfNeeded()
        }
    }

    @MainActor
    private func startAnimationIfNeeded() async {
        guard didStartAnimation == false else { return }
        didStartAnimation = true

        if reduceMotion {
            wordmarkOpacity = 1
            wordmarkScale = 1
            progressOpacity = 1
            await playHaptics()
            return
        }

        withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) {
            wordmarkOpacity = 1
            wordmarkScale = 1
        }

        withAnimation(.easeOut(duration: 0.5)) {
            progressOpacity = 1
        }

        await playHaptics()
    }

    @MainActor
    private func playHaptics() async {
        let events = LaunchSplashHapticsPlan.events(reduceMotion: reduceMotion)
        var elapsed: UInt64 = 0

        for event in events {
            let delta = event.delayNanoseconds > elapsed ? (event.delayNanoseconds - elapsed) : 0
            if delta > 0 {
                try? await Task.sleep(nanoseconds: delta)
            }
            switch event.kind {
            case .mediumImpact:
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.prepare()
                generator.impactOccurred(intensity: 1)
            case .rigidImpact:
                let generator = UIImpactFeedbackGenerator(style: .rigid)
                generator.prepare()
                generator.impactOccurred(intensity: 1)
            case .strongVibration:
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            case .successNotification:
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }
            elapsed = event.delayNanoseconds
        }
    }
}

private struct BrandWordmarkView: View {
    var body: some View {
        Text("millio")
            .font(.system(size: 56, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .foregroundStyle(AppColors.textPrimary)
    }
}

#Preview {
    LaunchingView()
}
