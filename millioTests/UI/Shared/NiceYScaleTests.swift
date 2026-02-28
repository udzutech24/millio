//
//  NiceYScaleTests.swift
//  millioTests
//
//  Тесты для NiceYScale - расчет красивой шкалы Y для графиков.
//

import Foundation
import Testing
@testable import millio

@Suite
struct NiceYScaleTests {

    // MARK: - Базовые тесты

    @Test("Пустой массив возвращает дефолтные значения")
    func testEmptyArray() {
        let scale = NiceYScale.make(values: [])

        #expect(scale.lower == 0)
        #expect(scale.upper == 1)
        #expect(scale.step == 1)
    }

    @Test("Одинаковые значения добавляют padding")
    func testSameValues() {
        let scale = NiceYScale.make(values: [100, 100, 100])

        // При одинаковых значениях должен быть отступ
        #expect(scale.lower < 100)
        #expect(scale.upper > 100)
        #expect(scale.step > 0)
    }

    // MARK: - Тесты диапазонов

    @Test("Маленькие значения (0-100)")
    func testSmallValues() {
        let scale = NiceYScale.make(values: [10, 50, 80])

        #expect(scale.lower < 10)
        #expect(scale.upper > 80)
        #expect(scale.step > 0)
    }

    @Test("Средние значения (тысячи)")
    func testMediumValues() {
        let scale = NiceYScale.make(values: [1_000, 5_000, 10_000])

        #expect(scale.lower < 1_000)
        #expect(scale.upper > 10_000)
        // Шаг должен быть кратен удобному числу
        let stepIsNice = scale.step == 1_000 || scale.step == 2_000 || scale.step == 5_000 || scale.step == 10_000
        #expect(stepIsNice)
    }

    @Test("Большие значения (миллионы) используют минимальный шаг 500K")
    func testLargeValues() {
        let scale = NiceYScale.make(values: [1_000_000, 2_000_000, 3_000_000])

        #expect(scale.step >= 500_000)
        #expect(scale.lower < 1_000_000)
        #expect(scale.upper > 3_000_000)
    }

    @Test("Отрицательные значения обрабатываются корректно")
    func testNegativeValues() {
        let scale = NiceYScale.make(values: [-100, -50, 0, 50])

        #expect(scale.lower < -100)
        #expect(scale.upper > 50)
        #expect(scale.step > 0)
    }

    // MARK: - Тесты с нулевой базой

    @Test("preferZeroBaseline включает ноль в диапазон")
    func testZeroBaseline() {
        let scaleWithZero = NiceYScale.make(values: [100, 200, 300], preferZeroBaseline: true)
        let scaleWithoutZero = NiceYScale.make(values: [100, 200, 300], preferZeroBaseline: false)

        #expect(scaleWithZero.lower <= 0)
        // Без preferZeroBaseline нижняя граница может быть выше нуля
        #expect(scaleWithoutZero.lower < 100)
    }

    // MARK: - Тесты шага

    @Test("Шаг кратен удобным числам (1, 2, 5, 10)")
    func testNiceStepValues() {
        let testCases: [[Double]] = [
            [0, 100],
            [0, 1000],
            [0, 10000],
            [0, 100000],
            [50, 150],
            [1000, 5000]
        ]

        for values in testCases {
            let scale = NiceYScale.make(values: values)

            // Находим порядок шага
            let logStep = log10(scale.step)
            let pow10 = pow(10.0, floor(logStep))
            let normalized = scale.step / pow10

            // Нормализованное значение должно быть близко к 1, 2, 5 или 10
            let isNice = abs(normalized - 1) < 0.01 ||
                         abs(normalized - 2) < 0.01 ||
                         abs(normalized - 5) < 0.01 ||
                         abs(normalized - 10) < 0.01

            #expect(isNice, "Шаг \(scale.step) должен быть 'красивым' для значений \(values)")
        }
    }

    // MARK: - Тесты padding

    @Test("Границы имеют padding для визуального отступа")
    func testPaddingExists() {
        let values = [100.0, 200.0, 300.0]
        let scale = NiceYScale.make(values: values)

        // Нижняя граница должна быть ниже минимума
        #expect(scale.lower < values.min()!)

        // Верхняя граница должна быть выше максимума
        #expect(scale.upper > values.max()!)
    }

    // MARK: - Тесты для реальных финансовых данных

    @Test("Типичный финансовый диапазон (100K - 500K)")
    func testTypicalFinanceRange() {
        let scale = NiceYScale.make(values: [100_000, 250_000, 400_000, 500_000])

        // Проверяем, что диапазон покрывает все значения
        #expect(scale.lower < 100_000)
        #expect(scale.upper > 500_000)

        // Проверяем, что можно построить тики от lower до upper с шагом step
        var tick = scale.lower
        var tickCount = 0
        while tick <= scale.upper && tickCount < 20 {
            tick += scale.step
            tickCount += 1
        }
        #expect(tickCount >= 2, "Должно быть минимум 2 тика на шкале")
    }

    @Test("Очень маленький диапазон (близкие значения)")
    func testVerySmallRange() {
        let scale = NiceYScale.make(values: [100.0, 100.5, 101.0])

        // Даже для маленького диапазона должен быть разумный шаг
        #expect(scale.step > 0)
        #expect(scale.upper > scale.lower)
    }
}
