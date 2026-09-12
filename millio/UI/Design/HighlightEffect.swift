//
//  HighlightEffect.swift
//  millio
//

import SwiftUI

/// Подсветка элемента, на который пользователя привёл чек-лист первых шагов.
/// Цель задаётся через `AppState.highlightTarget`, потому что подсветка живёт по другую
/// сторону навигации: карточка на дашборде, кнопка — на экране «Финансы».
private struct HighlightTargetModifier: ViewModifier {
    private enum Metrics {
        static let lineWidth: CGFloat = 2
        static let visibleSeconds: Double = 2
    }

    let id: String

    @Environment(AppState.self) private var appState
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .overlay {
                // Capsule, а не прямоугольник: единственная цель — круглая кнопка «+»,
                // на прямоугольном элементе капсула даст ту же обводку по краю.
                Capsule()
                    .stroke(AppColors.brandPrimary, lineWidth: Metrics.lineWidth)
                    .opacity(isVisible ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .task(id: appState.highlightTarget) {
                guard appState.highlightTarget == id else { return }
                withAnimation(AppAnimation.standard) { isVisible = true }
                try? await Task.sleep(for: .seconds(Metrics.visibleSeconds))
                guard !Task.isCancelled else { return }
                withAnimation(AppAnimation.standard) { isVisible = false }
                appState.highlightTarget = nil
            }
    }
}

extension View {
    /// Помечает элемент целью подсветки с идентификатором `id`.
    func highlightTarget(_ id: String) -> some View {
        modifier(HighlightTargetModifier(id: id))
    }
}
