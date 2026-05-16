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

    private var closeLabel: String {
        L("cashflow.common.close")
    }
    
    var body: some View {
        if isPresented {
            HStack(alignment: .top, spacing: AppSpacing.m) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.millioHeadline)
                    .foregroundStyle(AppColors.error)
                    .padding(.top, 2)

                Text(message)
                    .font(.millioBody)
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: AppSpacing.s)

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.millioCaption)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(closeLabel))
            }
            .padding(.horizontal, AppSpacing.l)
            .padding(.vertical, AppSpacing.m)
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
            .padding(.horizontal, AppSpacing.xxl)
            .padding(.bottom, 40)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(AppAnimation.spring, value: isPresented)
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
