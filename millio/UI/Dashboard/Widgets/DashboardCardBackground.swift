//
//  DashboardCardBackground.swift
//  millio
//

import SwiftUI

/// Единая подложка карточек дашборда (баланс, кэшфлоу, курсы валют).
/// Раньше каждый виджет дублировал один и тот же `RoundedRectangle` с плоской заливкой —
/// вынесено в общий компонент + добавлен тонкий вертикальный градиент вместо плоского цвета.
struct DashboardCardBackground: View {
    var cornerRadius: CGFloat = 20

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.075), Color.white.opacity(0.045)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
            )
    }
}
