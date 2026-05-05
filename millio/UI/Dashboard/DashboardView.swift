//
//  DashboardView.swift
//  millio
//

import SwiftUI

struct DashboardView: View {
    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.35))

                Text("Дашборд")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.55))

                Text("Скоро здесь появится сводка")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.30))

                Spacer()
            }
            .padding(.bottom, 72)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
