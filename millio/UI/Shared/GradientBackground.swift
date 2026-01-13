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
                    Color(hex: "19E694").opacity(0.0)
                ]),
                center: UnitPoint(x: 0.5, y: 0),
                startRadius: 0,
                endRadius: 500
            )
            .ignoresSafeArea()
            .shadow(color: Color(hex: "01A486").opacity(0.5), radius: 10, x: 10, y: 4)
            .shadow(color: Color(hex: "0061A7").opacity(0.5), radius: 10, x: -10, y: 4)
            
            // Нижний радиальный градиент (фиолетовый)
            RadialGradient(
                gradient: Gradient(colors: [
                    Color(hex: "BD00E7").opacity(1.0),
                    Color(hex: "BD00E7").opacity(0.0)
                ]),
                center: UnitPoint(x: 0.5, y: 1),
                startRadius: 0,
                endRadius: 500
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
                // Используем seed для стабильности
                var generator = SeededRandomNumberGenerator(seed: noiseSeed)
                // Density 50% означает половину точек от площади
                let pointCount = Int(size.width * size.height * 0.5)
                
                for _ in 0..<pointCount {
                    let x = Double.random(in: 0..<size.width, using: &generator)
                    let y = Double.random(in: 0..<size.height, using: &generator)
                    // Size 0.5 означает размер точки
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 0.5, height: 0.5)),
                        with: .color(.white.opacity(0.1)) // Opacity 10%
                    )
                }
            }
        }
    }
}
