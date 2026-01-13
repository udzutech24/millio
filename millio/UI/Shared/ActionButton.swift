//
//  ActionButton.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ActionButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 32, height: 32)
                    
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
                
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background {
                ZStack {
                    // Эффект стекла с blur
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.ultraThinMaterial)
                    
                    // Обводка с градиентом
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 2
                        )
                    
                    // Монотонный шум (эффект текстуры)
                    NoiseTexture()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .shadow(color: gradientColors.first?.opacity(0.5) ?? .clear, radius: 10, x: 10, y: 4)
            .shadow(color: gradientColors.last?.opacity(0.5) ?? .clear, radius: 10, x: -10, y: 4)
        }
        .buttonStyle(.plain)
    }
}

// Вспомогательный view для создания текстуры шума
private struct NoiseTexture: View {
    @State private var noiseSeed: Int = Int.random(in: 0..<10000)
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                // Используем seed для стабильности
                var generator = SeededRandomNumberGenerator(seed: noiseSeed)
                let pointCount = Int(size.width * size.height * 0.5)
                
                for _ in 0..<pointCount {
                    let x = Double.random(in: 0..<size.width, using: &generator)
                    let y = Double.random(in: 0..<size.height, using: &generator)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.5, height: 0.5)),
                        with: .color(.white.opacity(0.1))
                    )
                }
            }
        }
    }
}

// Генератор случайных чисел с seed для стабильности (используется в ActionButton и GradientBackground)
struct SeededRandomNumberGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: Int) {
        state = UInt64(seed)
    }
    
    mutating func next() -> UInt64 {
        state = state &* 1103515245 &+ 12345
        return state
    }
}
