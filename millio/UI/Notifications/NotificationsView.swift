//
//  NotificationsView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct NotificationsView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            ScrollView {
                VStack(spacing: 16) {
                    // Пример уведомления
                    NotificationCard(
                        icon: "sparkles",
                        title: "Добро пожаловать в millio!",
                        message: "Мы рады видеть вас! Начните использовать все возможности приложения уже сегодня.",
                        time: "Только что",
                        gradient: AppColors.incomeGradient
                    )
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationTitle("Уведомления")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Notification Card

private struct NotificationCard: View {
    let icon: String
    let title: String
    let message: String
    let time: String
    let gradient: [Color]
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Иконка
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 48, height: 48)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: gradient,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 2
                            )
                    }
                
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: gradient,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            // Контент
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                    
                    Spacer()
                    
                    Text(time)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(AppColors.textTertiary)
                }
                
                Text(message)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1.5
                        )
                }
        }
    }
}

#Preview {
    NavigationStack {
        NotificationsView()
    }
}
