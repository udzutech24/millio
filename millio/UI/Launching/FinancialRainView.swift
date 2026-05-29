//
//  FinancialRainView.swift
//  millio
//

import SwiftUI

struct FinancialRainView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            EmptyView()
        } else {
            RainCanvas()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Column model

private struct RainColumn {
    let x: CGFloat
    let speed: Double
    let phaseOffset: Double
    let trailLen: Int
}

// MARK: - Canvas

private struct RainCanvas: View {
    private static let symbols: [Character] = [
        "₽", "$", "€", "¥", "%", "↑", "↓", "+", "−",
        "0", "1", "2", "5", "8", "k", "m", "."
    ]
    private static let columnSpacing: CGFloat = 26
    private static let fontSize: CGFloat = 14
    private static let maxTrailLen = 18

    // Статические колонки — вычисляются один раз при загрузке типа, всегда готовы
    private static let columns: [RainColumn] = {
        var rng = SeededRNG(seed: 42)
        return (0..<22).map { col in
            let baseX = CGFloat(col) * columnSpacing + columnSpacing / 2
            let jitter = CGFloat(rng.next() % 7) - 3.0
            let speed = 90.0 + Double(rng.next() % 90)
            let phase = Double(rng.next() % 1000) / 1000.0
            let trailLen = 10 + rng.next() % 9
            return RainColumn(x: baseX + jitter, speed: speed, phaseOffset: phase, trailLen: trailLen)
        }
    }()

    @State private var startDate = Date()
    @State private var easterEggText = String(localized: "launch.rain.message")

    var body: some View {
        TimelineView(.animation) { ctx in
            Canvas { canvas, size in
                let elapsed = ctx.date.timeIntervalSince(startDate)
                drawRain(in: canvas, size: size, elapsed: elapsed)
                drawEasterEgg(in: canvas, size: size, elapsed: elapsed)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { startDate = Date() }
    }

    // MARK: Rain

    private func drawRain(in canvas: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let step = Self.fontSize * 1.6
        let topPad = CGFloat(Self.maxTrailLen) * step
        let totalTravel = Double(size.height + topPad)

        for (colIdx, col) in Self.columns.enumerated() {
            guard col.x < size.width + Self.columnSpacing else { continue }

            let cycleTime = totalTravel / col.speed
            let t = (elapsed + col.phaseOffset * cycleTime).truncatingRemainder(dividingBy: cycleTime)
            let headY = -topPad + CGFloat(t * col.speed)

            for i in 0..<col.trailLen {
                let y = headY - CGFloat(i) * step
                guard y > -step && y < size.height + step else { continue }

                let tick = Int(elapsed * 5.0) + colIdx * 13 + i * 7
                let char = Self.symbols[abs(tick) % Self.symbols.count]

                let color: Color
                let weight: Font.Weight
                if i == 0 {
                    color = .white
                    weight = .bold
                } else {
                    let fade = 1.0 - Double(i) / Double(col.trailLen)
                    color = AppColors.brandPrimary.opacity(fade * fade * 0.7)
                    weight = .regular
                }

                canvas.draw(
                    Text(String(char))
                        .font(.system(size: Self.fontSize, weight: weight, design: .monospaced))
                        .foregroundStyle(color),
                    at: CGPoint(x: col.x, y: y),
                    anchor: .center
                )
            }
        }
    }

    // MARK: Easter egg

    private func drawEasterEgg(in canvas: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let appearAt  = 1.5
        let holdUntil = 2.8
        let fadeOut   = 3.5

        let alpha: Double
        if elapsed < appearAt {
            return
        } else if elapsed < holdUntil {
            alpha = min(1, (elapsed - appearAt) / 0.6) * 0.85
        } else if elapsed < fadeOut {
            alpha = (1 - (elapsed - holdUntil) / (fadeOut - holdUntil)) * 0.85
        } else {
            return
        }

        canvas.draw(
            Text(easterEggText)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.brandPrimary.opacity(alpha))
                .tracking(4),
            at: CGPoint(x: size.width / 2, y: size.height / 2 + 130),
            anchor: .center
        )
    }
}

// MARK: - Seeded RNG

private struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Int {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Int((state >> 33) & 0x7FFF_FFFF)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        FinancialRainView()
    }
}
