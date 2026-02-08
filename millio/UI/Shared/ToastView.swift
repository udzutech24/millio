//
//  ToastView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ToastView: View {
    let message: String
    @Binding var isPresented: Bool
    
    var body: some View {
        if isPresented {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.error)
                
                Text(message)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(2)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [AppColors.error.opacity(0.5), AppColors.error.opacity(0.3)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
        }
    }
}

#Preview {
    ZStack {
        GradientBackground()
        
        VStack {
            Spacer()
            
            ToastView(message: "Ошибка при обновлении курсов", isPresented: .constant(true))
        }
    }
}
