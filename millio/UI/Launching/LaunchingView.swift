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
    @State private var backdropOffset: CGSize = CGSize(width: -80, height: 0)
    @State private var backdropScale: CGFloat = 1.08
    @State private var wordmarkOpacity: Double = 0
    @State private var wordmarkScale: CGFloat = 0.92
    @State private var contentOffsetX: CGFloat = -128
    @State private var contentOffsetY: CGFloat = 22
    @State private var progressOpacity: Double = 0
    @State private var shimmerOffset: CGFloat = -220
    
    var body: some View {
        ZStack {
            SplashBackdropView(offset: backdropOffset, scale: backdropScale)
            
            VStack(spacing: 28) {
                ZStack {
                    BrandWordmarkView()
                        .overlay {
                            SplashWordmarkShimmer(offsetX: shimmerOffset)
                                .mask(BrandWordmarkView())
                        }
                }
                .scaleEffect(wordmarkScale)
                .opacity(wordmarkOpacity)
                
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .scaleEffect(1.15)
                    .opacity(progressOpacity)
            }
            .offset(x: contentOffsetX, y: contentOffsetY)
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
            contentOffsetX = 0
            contentOffsetY = 0
            progressOpacity = 1
            await playHaptics()
            return
        }

        withAnimation(.spring(response: 0.8, dampingFraction: 0.82)) {
            wordmarkOpacity = 1
            wordmarkScale = 1
            contentOffsetX = 0
            contentOffsetY = 0
        }

        withAnimation(.easeOut(duration: 0.5)) {
            progressOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.9)) {
            backdropOffset = CGSize(width: 90, height: 0)
            backdropScale = 1.12
        }

        withAnimation(.easeInOut(duration: 1.15).delay(0.35)) {
            shimmerOffset = 220
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

private struct SplashBackdropView: View {
    let offset: CGSize
    let scale: CGFloat

    var body: some View {
        Image("LaunchImage")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .scaleEffect(scale)
            .offset(offset)
            .clipped()
            .ignoresSafeArea()
    }
}

private struct SplashWordmarkShimmer: View {
    let offsetX: CGFloat

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.white.opacity(0.85),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 110)
            .rotationEffect(.degrees(18))
            .offset(x: offsetX)
            .blendMode(.screen)
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
