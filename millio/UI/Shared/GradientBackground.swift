//
//  GradientBackground.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct GradientBackground: View {
    var body: some View {
        ZStack {
            // Основной цвет фона
            Color(hex: "161C29")
                .ignoresSafeArea()
            
            // Верхний радиальный градиент (зеленоватый)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: "19E694").opacity(1.0),
                    Color(hex: "0081E7").opacity(0.05)
                ]),
                center: UnitPoint(x: 1.3, y: 0),
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .shadow(color: Color(hex: "01A486").opacity(0.3), radius: 10, x: 10, y: 4)
            .shadow(color: Color(hex: "0061A7").opacity(0.3), radius: 10, x: -10, y: 4)
            .blur(radius: 50)
            
            // Нижний радиальный градиент (фиолетовый)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: "BD00E7").opacity(1.0),
                    Color(hex: "196EE6").opacity(0.05)
                ]),
                center: UnitPoint(x: 0.5, y: 1.2),
                startRadius: 0,
                endRadius: 400
            )
            .ignoresSafeArea()
            .blur(radius: 100) // Layer blur для эффекта стекла
            
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

