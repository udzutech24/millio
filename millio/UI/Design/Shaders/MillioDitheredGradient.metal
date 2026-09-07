//
//  MillioDitheredGradient.metal
//  millio
//
//  Единственный шейдер проекта: фиолетовый градиент с пиксельной дизеринг-текстурой.
//  Фаза 4 плана plans/2026-09-05__planned-operations-applied-notice.md.
//
//  Вызывается только через `View.ditheredGradient(phase:)` (UI/Design/DitheredGradientEffect.swift).
//  Имя функции глобально уникально в default.metallib — отсюда префикс `millio`.
//

#include <metal_stdlib>

using namespace metal;

/// Матрица Байера 4×4 — упорядоченный дизеринг. Порог зависит только от координаты пикселя,
/// поэтому текстура стабильна между кадрами: случайный шум на каждом кадре читался бы как
/// мерцание, а не как «пиксельная» поверхность.
constant float kMillioBayer4x4[16] = {
     0.0 / 16.0,  8.0 / 16.0,  2.0 / 16.0, 10.0 / 16.0,
    12.0 / 16.0,  4.0 / 16.0, 14.0 / 16.0,  6.0 / 16.0,
     3.0 / 16.0, 11.0 / 16.0,  1.0 / 16.0,  9.0 / 16.0,
    15.0 / 16.0,  7.0 / 16.0, 13.0 / 16.0,  5.0 / 16.0
};

/// Границы градиента: те же 6A5CFF → D02BFF, что у `AppColors.cashflowGradient`.
constant half3 kMillioGradientStart = half3(0.416h, 0.361h, 1.000h);
constant half3 kMillioGradientEnd   = half3(0.816h, 0.169h, 1.000h);

/// Красит пиксель фигуры градиентом с дизерингом.
///
/// - position: координата пикселя внутри вью;
/// - color: исходный цвет; используется ТОЛЬКО его альфа — как маска фигуры (сглаженные углы);
/// - size: размер вью в точках, приходит из `visualEffect`;
/// - phase: 0 — момент появления (крупная сетка, мало ступеней), 1 — осевшее состояние;
/// - pixelSize: сторона ячейки дизеринга в точках.
[[ stitchable ]] half4 millioDitheredGradient(
    float2 position,
    half4 color,
    float2 size,
    float phase,
    float pixelSize
) {
    // Вне фигуры (и в её прозрачных углах) не рисуем ничего: маска — альфа исходного цвета.
    if (color.a <= 0.0h) {
        return color;
    }

    float2 extent = max(size, float2(1.0, 1.0));
    float cell = max(pixelSize, 1.0);
    float2 pixel = floor(position / cell);
    float2 uv = clamp((pixel * cell) / extent, 0.0, 1.0);

    // Диагональный ход градиента. На появлении он сдвинут: цвет «проезжает» по шапке,
    // к phase = 1 встаёт в штатное положение.
    float t = clamp(uv.x * 0.62 + uv.y * 0.38 + (1.0 - phase) * 0.30, 0.0, 1.0);
    half3 base = mix(kMillioGradientStart, kMillioGradientEnd, half(t));

    // Квантование по порогу Байера: вместо гладкого перехода — ступени, а на их границах
    // пиксели двух соседних ступеней перемешиваются в шахматном порядке. Это и есть дизеринг.
    int index = int(fmod(pixel.y, 4.0)) * 4 + int(fmod(pixel.x, 4.0));
    half threshold = half(kMillioBayer4x4[index]);
    half levels = half(mix(3.0, 7.0, phase));
    half3 quantized = floor(base * levels + threshold) / levels;

    // Шахматная сетка поверх градиента: соседние ячейки чуть темнее/светлее. К phase = 1
    // амплитуда падает — иначе шапка рябила бы под текстом постоянно.
    half checker = half(fmod(pixel.x + pixel.y, 2.0));
    half amplitude = half(mix(0.20, 0.07, phase));
    half3 rgb = quantized * (1.0h - amplitude * checker);

    // Светлая полоса, идущая вместе с фазой: живёт только во время появления.
    float band = exp(-pow((t - phase) * 5.0, 2.0)) * (1.0 - phase);
    rgb = clamp(rgb + half3(half(band * 0.35)), 0.0h, 1.0h);

    // SwiftUI ждёт премультиплицированный цвет.
    return half4(rgb * color.a, color.a);
}
