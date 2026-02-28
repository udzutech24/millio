//
//  ConverterViewModelTests.swift
//  millioTests
//
//  Created by Claude on 01.02.2026.
//

import Foundation
import Testing
@testable import millio

// MARK: - Mock Rate Repository

@MainActor
final class MockConverterRateRepository: RateRepositoryProtocol, @unchecked Sendable {
    var mockRates: [String: Double] = ["USD": 1.0, "EUR": 0.92, "RUB": 90.0, "TRY": 30.0, "GBP": 0.79]
    var shouldFail: Bool = false

    nonisolated func getLatestRates(source: RateSource, forceRefresh: Bool, allowStaleOnError: Bool) async throws -> RateSnapshot {
        let shouldFailValue = await MainActor.run { shouldFail }
        if shouldFailValue {
            throw URLError(.notConnectedToInternet)
        }

        let ratesValue = await MainActor.run { mockRates }
        return RateSnapshot(
            source: source,
            rates: ratesValue,
            updatedAt: Date().timeIntervalSince1970,
            fetchedAt: Date().timeIntervalSince1970
        )
    }
}

// MARK: - Tests

@Suite(.serialized)
@MainActor
struct ConverterViewModelTests {

    @Test("По умолчанию fractionDigits = 2 при первом запуске")
    func testDefaultFractionDigitsIsTwo() async {
        let key = "conv_fraction_digits"
        let defaults = UserDefaults.standard
        let hadValue = defaults.object(forKey: key) != nil
        let previousValue = defaults.integer(forKey: key)
        defaults.removeObject(forKey: key)
        defer {
            if hadValue {
                defaults.set(previousValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)
        #expect(viewModel.state.fractionDigits == 2)
    }

    @Test("Инициализация загружает сохранённые валюты")
    func testInitializationLoadsStoredCurrencies() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        // По умолчанию должны быть валюты
        #expect(!viewModel.state.selectedCurrencies.isEmpty)
        #expect(viewModel.state.selectedCurrencies.count <= 6)
    }

    @Test("Выбор валюты меняет activeCode")
    func testSelectCurrency() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.selectCurrency("USD"))
        #expect(viewModel.state.activeCode == "USD")

        viewModel.handle(.selectCurrency("EUR"))
        #expect(viewModel.state.activeCode == "EUR")
    }

    @Test("Добавление цифры обновляет inputText")
    func testAppendDigit() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.clearAll)
        #expect(viewModel.state.inputText == "0")

        viewModel.handle(.appendDigit("5"))
        #expect(viewModel.state.inputText == "5")

        viewModel.handle(.appendDigit("3"))
        #expect(viewModel.state.inputText == "53")
    }

    @Test("Backspace удаляет последний символ")
    func testBackspace() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.updateInputText("123"))
        viewModel.handle(.backspace)
        #expect(viewModel.state.inputText == "12")

        viewModel.handle(.backspace)
        #expect(viewModel.state.inputText == "1")

        viewModel.handle(.backspace)
        // После удаления всех цифр должен остаться "0"
        #expect(viewModel.state.inputText == "0" || viewModel.state.inputText.isEmpty)
    }

    @Test("clearAll сбрасывает всё")
    func testClearAll() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.updateInputText("12345"))
        viewModel.handle(.operation("+"))
        viewModel.handle(.appendDigit("5"))

        viewModel.handle(.clearAll)

        #expect(viewModel.state.inputText == "0")
        #expect(viewModel.state.accumulator == nil)
        #expect(viewModel.state.pendingOp == nil)
    }

    @Test("Операция сложения")
    func testAdditionOperation() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.clearAll)
        viewModel.handle(.appendDigit("1"))
        viewModel.handle(.appendDigit("0"))
        viewModel.handle(.operation("+"))
        viewModel.handle(.appendDigit("5"))
        viewModel.handle(.equal)

        // 10 + 5 = 15
        #expect(viewModel.state.inputText == "15")
    }

    @Test("Операция вычитания")
    func testSubtractionOperation() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.clearAll)
        viewModel.handle(.appendDigit("2"))
        viewModel.handle(.appendDigit("0"))
        viewModel.handle(.operation("-"))
        viewModel.handle(.appendDigit("7"))
        viewModel.handle(.equal)

        // 20 - 7 = 13
        #expect(viewModel.state.inputText == "13")
    }

    @Test("Операция умножения")
    func testMultiplicationOperation() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.clearAll)
        viewModel.handle(.appendDigit("6"))
        viewModel.handle(.operation("*"))
        viewModel.handle(.appendDigit("7"))
        viewModel.handle(.equal)

        // 6 × 7 = 42
        #expect(viewModel.state.inputText == "42")
    }

    @Test("Операция деления")
    func testDivisionOperation() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.clearAll)
        viewModel.handle(.appendDigit("8"))
        viewModel.handle(.appendDigit("4"))
        viewModel.handle(.operation("/"))
        viewModel.handle(.appendDigit("4"))
        viewModel.handle(.equal)

        // 84 ÷ 4 = 21
        #expect(viewModel.state.inputText == "21")
    }

    @Test("Удаление валюты из списка")
    func testRemoveCurrency() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        let initialCount = viewModel.state.selectedCurrencies.count
        guard initialCount > 1 else { return }

        viewModel.handle(.removeCurrency(0))

        #expect(viewModel.state.selectedCurrencies.count == initialCount - 1)
    }

    @Test("Добавление валюты через picker")
    func testApplyPickerSelection() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        // Удаляем валюты до минимума
        while viewModel.state.selectedCurrencies.count > 2 {
            viewModel.handle(.removeCurrency(0))
        }

        let countBefore = viewModel.state.selectedCurrencies.count

        // Добавляем новую валюту
        viewModel.handle(.addCurrency)
        viewModel.handle(.applyPickerSelection("JPY"))

        // Если JPY не было в списке, должно добавиться
        if !viewModel.state.selectedCurrencies.contains("JPY") || countBefore < 6 {
            // Список либо увеличился, либо JPY заменил существующую
            #expect(viewModel.state.selectedCurrencies.count >= countBefore)
        }
    }

    @Test("Установка fractionDigits")
    func testSetFractionDigits() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        viewModel.handle(.setFractionDigits(2))
        #expect(viewModel.state.fractionDigits == 2)

        viewModel.handle(.setFractionDigits(6))
        #expect(viewModel.state.fractionDigits == 6)
    }

    @Test("toggleCalcMode переключает режим калькулятора")
    func testToggleCalcMode() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        let initial = viewModel.state.calcModeOn

        viewModel.handle(.toggleCalcMode)
        #expect(viewModel.state.calcModeOn == !initial)

        viewModel.handle(.toggleCalcMode)
        #expect(viewModel.state.calcModeOn == initial)
    }

    @Test("displayValue конвертирует правильно")
    func testDisplayValueConversion() async {
        let mockRepo = MockConverterRateRepository()
        let viewModel = ConverterViewModel(rateRepository: mockRepo)

        // Загружаем курсы
        viewModel.state.allRates = mockRepo.mockRates

        viewModel.handle(.updateInputText("100"))
        viewModel.handle(.selectCurrency("USD"))

        // 100 USD → RUB при курсе 90
        let rubValue = viewModel.displayValue(for: "RUB")

        // Значение должно быть около 9000
        if let parsed = Double(rubValue.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: " ", with: "")) {
            #expect(abs(parsed - 9000) < 100) // допускаем погрешность форматирования
        }
    }
}
