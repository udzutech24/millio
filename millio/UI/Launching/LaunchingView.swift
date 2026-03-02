//
//  LaunchingView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct LaunchingView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0.5
    @State private var subtitleWidth: CGFloat = 0
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 32) {
                // Логотип приложения
                VStack(spacing: 16) {
                    BrandWordmarkView(targetWidth: subtitleWidth)
                        .scaleEffect(scale)
                        .opacity(opacity)
                    
                    Text("ваш лучший помощник")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear {
                                        subtitleWidth = proxy.size.width
                                    }
                                    .onChange(of: proxy.size.width) { newValue in
                                        subtitleWidth = newValue
                                    }
                            }
                        )
                        .opacity(opacity)
                }
                
                // Индикатор загрузки
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .scaleEffect(1.2)
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }
}

private struct BrandWordmarkView: View {
    let targetWidth: CGFloat

    private static let brandDotColor = Color(hex: "FFC928")
    private static let dotXFactor: CGFloat = 0.638
    private static let dotYFactor: CGFloat = 0.108

    var body: some View {
        Text("mill\u{0131}o")
            .font(.system(size: 56, weight: .bold))
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .foregroundStyle(AppColors.textPrimary)
            .frame(width: targetWidth > 0 ? targetWidth : nil)
            .overlay(alignment: .topLeading) {
                GeometryReader { proxy in
                    Circle()
                        .fill(Self.brandDotColor)
                        .frame(width: 12, height: 12)
                        .position(
                            x: proxy.size.width * Self.dotXFactor,
                            y: proxy.size.height * Self.dotYFactor
                        )
                }
            }
    }
}

#Preview {
    LaunchingView()
}
