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
    /// Ключ сообщения оверлея — по умолчанию «Переключение профиля…».
    /// Reconciliation (Track B) переиспользует оверлей с «Восстанавливаю данные…».
    var messageKey: String.LocalizationValue = "app.scope.switching"

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: AppSpacing.l) {
                ProgressView()
                    .tint(AppColors.textPrimary)
                    .scaleEffect(1.15)

                Text(L(messageKey))
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
