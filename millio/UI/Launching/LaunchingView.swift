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
    
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack(spacing: 32) {
                // Логотип приложения
                VStack(spacing: 16) {
                    Text("millio")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [AppColors.textPrimary, AppColors.textSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(scale)
                        .opacity(opacity)
                    
                    Text("ваш лучший помощник")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(AppColors.textSecondary)
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

#Preview {
    LaunchingView()
}
