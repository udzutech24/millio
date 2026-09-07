//
//  DitheredGradientEffect.swift
//  millio
//
//  Swift-обёртка единственного шейдера проекта (UI/Design/Shaders/MillioDitheredGradient.metal).
//  Фаза 4 плана plans/2026-09-05__planned-operations-applied-notice.md.
//

import SwiftUI

/// Сторона ячейки дизеринга в точках. Мельче — текстура пропадает на Retina, крупнее —
/// шапка распадается на квадраты и мешает читать заголовок.
/// Вне типа: аргументы шейдера собираются в `Sendable`-замыкании `visualEffect`, куда
/// `@MainActor`-изолированное свойство не пролезает.
private let ditherPixelSize: Double = 3

/// Пиксельный дизеринг-градиент на Metal.
private struct DitheredGradientEffect: ViewModifier, Animatable {

    var phase: Double

    // Аргументы шейдера SwiftUI сама не интерполирует: без `Animatable` фаза перескочила бы
    // из 0 в 1 одним кадром и появления не было бы видно вовсе.
    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func body(content: Content) -> some View {
        content.visualEffect { view, proxy in
            view.colorEffect(
                ShaderLibrary.default.millioDitheredGradient(
                    .float2(proxy.size),
                    .float(phase),
                    .float(ditherPixelSize)
                )
            )
        }
    }
}

extension View {
    /// Красит непрозрачные пиксели фигуры фиолетовым градиентом с дизеринг-текстурой.
    ///
    /// Применять к фигуре-подложке, а не к содержимому: `colorEffect` перекрашивает каждый
    /// непрозрачный пиксель, включая текст.
    ///
    /// - Parameter phase: 0 — момент появления, 1 — осевшее состояние. Анимируется
    ///   `withAnimation`, промежуточные значения интерполирует `Animatable`.
    func ditheredGradient(phase: Double) -> some View {
        modifier(DitheredGradientEffect(phase: phase))
    }
}
