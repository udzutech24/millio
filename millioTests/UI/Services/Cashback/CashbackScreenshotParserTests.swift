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

    @Test("Парсер выдерживает OCR-шум с фото экрана банка")
    func testParseRecognizedLinesSupportsPhotoLikeOcrNoise() {
        let lines = [
            "Ваши категории на март",
            "🛍️ 10°/o Маркетплейсы",
            "💄 10 % Красота",
            "👗 10%Одежда и обувь i",
            "📶 10％ Связь, интернет и ТВ",
            "🌷 10% Цветы"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 5)
        #expect(parsed.contains { $0.categoryName == "Маркетплейсы" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Красота" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Одежда и обувь" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Связь, интернет и ТВ" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Цветы" && $0.percentage == 10 })
    }

    @Test("Парсер поддерживает формат категории слева и процента справа")
    func testParseRecognizedLinesSupportsCategoryThenPercentForYandexPayLikeLayout() {
        let lines = [
            "Кешбэк при оплате онлайн и на кассе",
            "Все покупки",
            "+2%",
            "Цветы",
            "+10%",
            "Супермаркеты",
            "+5%",
            "Кешбэк в Яндекс Такси",
            "Комфорт",
            "+5%",
            "Комфорт+",
            "+5%",
            "Ultima",
            "+5%",
            "Кешбэк по категориям",
            "Яндекс Лавка ↗",
            "+5%",
            "Полис ОСАГО ↗",
            "+15%",
            "с Яндекс Заботой",
            "Больше кешбэка от партнёров"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 8)
        #expect(parsed.contains { $0.categoryName == "Все покупки" && $0.percentage == 2 })
        #expect(parsed.contains { $0.categoryName == "Цветы" && $0.percentage == 10 })
        #expect(parsed.contains { $0.categoryName == "Супермаркеты" && $0.percentage == 5 })
        #expect(parsed.contains { $0.categoryName == "Комфорт" && $0.percentage == 5 })
        #expect(parsed.contains { $0.categoryName == "Комфорт+" && $0.percentage == 5 })
        #expect(parsed.contains { $0.categoryName == "Ultima" && $0.percentage == 5 })
        #expect(parsed.contains { $0.categoryName == "Яндекс Лавка" && $0.percentage == 5 })
        #expect(parsed.contains { $0.categoryName == "Полис ОСАГО" && $0.percentage == 15 })
    }

    @Test("Парсер поддерживает карточку с единичной категорией")
    func testParseRecognizedLinesSupportsSinglePromoCard() {
        let lines = [
            "7%",
            "Активный отдых",
            "Отдыхайте с выгодой!"
        ]

        let parsed = CashbackScreenshotParser.parseRecognizedLines(lines)

        #expect(parsed.count == 1)
        #expect(parsed.first == CashbackScreenshotImportItem(categoryName: "Активный отдых", percentage: 7))
    }
}
