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
            
            // Верхний градиент (если цвета заданы)
            if let topStart = hexToColor(topGradientColor),
               let topEnd = hexToColor(topGradientFadeColor) {
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            topStart.opacity(0.3),
                            topEnd.opacity(0.1),
                            Color.clear
                        ]),
                        startPoint: .top,
                        endPoint: .center
                    )
                    .frame(height: geometry.size.height / 3)
                    .frame(maxHeight: .infinity, alignment: .top)
                }
                .ignoresSafeArea()
            }
            
            // Нижний градиент (если цвета заданы)
            if let bottomStart = hexToColor(bottomGradientColor),
               let bottomEnd = hexToColor(bottomGradientFadeColor) {
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.clear,
                            bottomEnd.opacity(0.1),
                            bottomStart.opacity(0.3)
                        ]),
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height / 3)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .ignoresSafeArea()
            }
            
           
        }
    }
    
    // Конвертация hex-строки в Color
    private func hexToColor(_ hex: String?) -> Color? {
        guard let hex = hex else { return nil }
        
        let trimmedHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanHex = trimmedHex.hasPrefix("#") ? String(trimmedHex.dropFirst()) : trimmedHex
        
        guard cleanHex.count == 6,
              let rgb = UInt32(cleanHex, radix: 16) else {
            return nil
        }
        
        let red = Double((rgb >> 16) & 0xFF) / 255.0
        let green = Double((rgb >> 8) & 0xFF) / 255.0
        let blue = Double(rgb & 0xFF) / 255.0
        
        return Color(red: red, green: green, blue: blue)
    }
}
