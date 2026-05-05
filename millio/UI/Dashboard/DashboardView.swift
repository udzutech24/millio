//
//  DashboardView.swift
//  millio
//

import SwiftUI

struct DashboardView: View {
    var onOpenConverter: () -> Void = {}
    var onOpenCashback: () -> Void = {}

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(alignment: .leading, spacing: 0) {
                // Мини-приложения
                miniAppsSection
                    .padding(.top, 12)

                Spacer()

                // Плейсхолдер
                VStack(spacing: 16) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 48, weight: .thin))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.35))

                    Text("Дашборд")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.55))

                    Text("Скоро здесь появится сводка")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(0.30))
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
            .padding(.bottom, 72)
        }
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Мини-приложения

    private var miniAppsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                miniAppChip(
                    icon: "arrow.2.squarepath",
                    titleKey: MainLocalization.serviceCourses,
                    action: onOpenConverter
                )
                miniAppChip(
                    icon: "percent",
                    titleKey: MainLocalization.serviceCashback,
                    action: onOpenCashback
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
        }
    }

    private func miniAppChip(icon: String, titleKey: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(MainLocalization.text(titleKey))
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(AppColors.textPrimary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.12))
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.20), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
