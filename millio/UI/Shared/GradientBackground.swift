//
//  GradientBackground.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct GradientBackground: View {
    // Кастомные цвета для градиентов (опционально)
    var topGradientColor: String? = nil
    var topGradientFadeColor: String? = nil
    var bottomGradientColor: String? = nil
    var bottomGradientFadeColor: String? = nil
    
    var body: some View {
        ZStack {
            // Основной цвет фона
            Color.black
                .ignoresSafeArea()
            
            // Монотонный шум (текстура)
            NoiseTexture()
                .ignoresSafeArea()
        }
    }
}

// Вспомогательный view для создания текстуры шума
private struct NoiseTexture: View {
    @State private var noiseSeed: Int = Int.random(in: 0..<10000)
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                var generator = SeededRandomNumberGenerator(seed: noiseSeed)

                // Меньшая плотность
                let pointCount = Int(size.width * size.height * 0.15)

                for _ in 0..<pointCount {
                    let x = Double.random(in: 0..<size.width, using: &generator)
                    let y = Double.random(in: 0..<size.height, using: &generator)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.4, height: 0.4)),
                        with: .color(.white.opacity(0.05)) // Мягкий шум
                    )
                }
            }
        }
    }
}


// Генератор случайных чисел с seed для стабильности (используется в GradientBackground)
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

