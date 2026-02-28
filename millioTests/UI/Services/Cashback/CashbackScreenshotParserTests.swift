//
//  CashbackScreenshotParserTests.swift
//  millioTests
//
//  Created by Codex on 26.02.2026.
//

import Testing
@testable import millio

struct CashbackScreenshotParserTests {
    @Test("Парсер извлекает кешбэк-строки и игнорирует шум")
    func testParseRecognizedLinesExtractsCashbackRows() {
        let lines = [
            "10 категорий в феврале",
            "1% За все покупки",
            "7% Техника",
            "Для зарплатных клиентов",
            "до 10% Отели в Тревел",
            "Условия программы лояльности",
            "до 7% Альфа-Заправки"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 4)
        #expect(parsed.contains { $0.categoryName == "За все покупки" && $0.percentage == 1 })
        #expect(parsed.contains { $0.categoryName == "Техника" && $0.percentage == 7 })
        #expect(parsed.contains { $0.categoryName == "Отели в Тревел" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Альфа-Заправки" && $0.percentage == 7 })
    }

    @Test("Парсер поддерживает формат, где процент и категория на соседних строках")
    func testParseRecognizedLinesSupportsSplitRows() {
        let lines = [
            "5%",
            "Супермаркеты",
            "5%",
            "Рестораны"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 2)
        #expect(parsed[0] == CashbackScreenshotImportItem(categoryName: "Супермаркеты", percentage: 5))
        #expect(parsed[1] == CashbackScreenshotImportItem(categoryName: "Рестораны", percentage: 5))
    }

    @Test("Дубликаты категорий склеиваются с максимальным процентом")
    func testParseRecognizedLinesDeduplicatesByCategory() {
        let lines = [
            "5% Топливо и АЗС",
            "до 7% Топливо и АЗС",
            "1% Все покупки"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 2)
        #expect(parsed.contains { $0.categoryName == "Топливо и АЗС" && $0.percentage == 7 })
        #expect(parsed.contains { $0.categoryName == "Все покупки" && $0.percentage == 1 })
    }

    @Test("Парсер поддерживает формат категории с процентом в конце строки")
    func testParseRecognizedLinesSupportsTrailingPercentFormat() {
        let lines = [
            "Кешбэк при оплате онлайн и на кассе",
            "Все покупки +2%",
            "Кафе, бары и рестораны +7%",
            "Аптеки +10%",
            "Кешбэк в Яндекс Такси",
            "Эконом +15%"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 4)
        #expect(parsed.contains { $0.categoryName == "Все покупки" && $0.percentage == 2 })
        #expect(parsed.contains { $0.categoryName == "Кафе, бары и рестораны" && $0.percentage == 7 })
        #expect(parsed.contains { $0.categoryName == "Аптеки" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Эконом" && $0.percentage == 15 })
    }

    @Test("Парсер поддерживает процент со знаком плюс на отдельной строке")
    func testParseRecognizedLinesSupportsSplitRowsWithPlusSign() {
        let lines = [
            "+2%",
            "Все покупки",
            "＋7%",
            "Кафе"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 2)
        #expect(parsed.contains { $0.categoryName == "Все покупки" && $0.percentage == 2 })
        #expect(parsed.contains { $0.categoryName == "Кафе" && $0.percentage == 7 })
    }
}
