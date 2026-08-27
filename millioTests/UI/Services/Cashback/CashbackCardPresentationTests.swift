//
//  CashbackCardPresentationTests.swift
//  millioTests
//
//  6b Путь B, Ф5c.4: presentation кэшбэк-пикера переведён с легаси `Card` на единый
//  `CashflowSelectableAccount` (карты ∪ core-счета). Богатая мета (банк/тип/маска/баланс/лимит)
//  убрана — у core `Account` её нет; строка несёт имя + валюту.
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashbackCardPresentationTests {
    private func account(
        title: String,
        currency: String = "RUB",
        cardID: String = "id-1",
        isFavorite: Bool = false
    ) -> CashflowSelectableAccount {
        CashflowSelectableAccount(
            kind: .legacyCard(cardID: cardID),
            title: title,
            currency: currency,
            isFavorite: isFavorite,
            prioritySortOrder: 0,
            updatedAt: Date()
        )
    }

    @Test("Заголовок возвращает имя счёта, если оно задано")
    func testTitleReturnsName() {
        let subject = account(title: "T-Bank Black")
        #expect(CashbackCardPresentation.title(for: subject, locale: Locale(identifier: "en")) == "T-Bank Black")
    }

    @Test("Пустое имя заменяется локализованным фолбэком (en / zh-Hans)")
    func testTitleFallsBackWhenEmpty() {
        let subject = account(title: "   ")
        #expect(CashbackCardPresentation.title(for: subject, locale: Locale(identifier: "en")) == "Untitled card")
        #expect(CashbackCardPresentation.title(for: subject, locale: Locale(identifier: "zh-Hans")) == "未命名卡片")
    }

    @Test("Подзаголовок — валюта счёта")
    func testSubtitleIsCurrency() {
        let subject = account(title: "Wise", currency: "EUR")
        #expect(CashbackCardPresentation.subtitle(for: subject) == "EUR")
        #expect(CashbackCardPresentation.pickerSubtitle(for: subject) == "EUR")
    }

    @Test("Явная locale фолбэка не протекает через активный язык приложения")
    func testTitleUsesRequestedLocaleEvenWhenAppLanguageDiffers() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.simplifiedChinese)

        let subject = account(title: "")
        #expect(CashbackCardPresentation.title(for: subject, locale: Locale(identifier: "en")) == "Untitled card")
    }
}
