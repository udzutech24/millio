//
//  ScopeSwitchOverlayView.swift
//  millio
//
//  Переходный оверлей на время смены скоупа данных (login/logout/force-signout).
//  Показывается, пока пересоздаётся дерево на новом контейнере (см. scope-token в millioApp),
//  чтобы пользователь не видел мигание старых/чужих данных при переключении профиля (риск №7).
//

import SwiftUI

struct ScopeSwitchOverlayView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: AppSpacing.l) {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .scaleEffect(1.15)

                Text(L("app.scope.switching"))
                    .font(.millioHeadline)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .transition(.opacity)
    }
}

#Preview {
    ScopeSwitchOverlayView()
}
