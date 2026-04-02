//
//  CashbackCardPresentationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashbackCardPresentationTests {
    @Test("Подзаголовок карты включает банк, тип и маску номера")
    func testSubtitleIncludesBankTypeAndMaskedNumber() {
        let card = Card(
            name: "T-Bank Black",
            cardNumber: "1234",
            bank: .tinkoff,
            cardType: .debit,
            currency: "RUB",
            balance: 1500
        )

        let subtitle = CashbackCardPresentation.subtitle(for: card)

        #expect(subtitle.contains(card.bank.displayName))
        #expect(subtitle.contains(card.cardType.displayName))
        #expect(subtitle.contains("•••• 1234"))
    }

    @Test("Подзаголовок picker держит только банк и тип без маски номера")
    func testPickerSubtitleKeepsPrimaryMetadataCompact() {
        let card = Card(
            name: "T-Bank Black",
            cardNumber: "1234",
            bank: .tinkoff,
            cardType: .debit,
            currency: "RUB",
            balance: 1500
        )

        let subtitle = CashbackCardPresentation.pickerSubtitle(for: card)

        #expect(subtitle == "\(card.bank.displayName) • \(card.cardType.displayName)")
        #expect(!subtitle.contains("1234"))
    }

    @Test("Детали кредитной карты показывают баланс и лимит")
    func testDetailIncludesBalanceAndLimitForCreditCard() {
        let card = Card(
            name: "Credit",
            cardNumber: "9876",
            bank: .alfa,
            cardType: .credit,
            currency: "RUB",
            balance: 12500,
            creditLimit: 50000
        )

        let detail = CashbackCardPresentation.detail(for: card, locale: Locale(identifier: "ru"))

        #expect(detail.contains("Баланс 12 500 RUB"))
        #expect(detail.contains("Лимит 50 000 RUB"))
    }

    @Test("Детали picker добавляют маску номера после финансовых данных")
    func testPickerDetailAddsMaskedNumber() {
        let card = Card(
            name: "Credit",
            cardNumber: "9876",
            bank: .alfa,
            cardType: .credit,
            currency: "RUB",
            balance: 12500,
            creditLimit: 50000
        )

        let detail = CashbackCardPresentation.pickerDetail(for: card, locale: Locale(identifier: "ru"))

        #expect(detail.contains("Баланс 12 500 RUB"))
        #expect(detail.contains("Лимит 50 000 RUB"))
        #expect(detail.contains("•••• 9876"))
    }

    @Test("Явная locale для picker detail не протекает через активный язык приложения")
    func testPickerDetailUsesRequestedLocaleEvenWhenAppLanguageDiffers() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }
        LanguageManager.shared.setLanguage(.simplifiedChinese)

        let card = Card(
            name: "Credit",
            cardNumber: "9876",
            bank: .alfa,
            cardType: .credit,
            currency: "RUB",
            balance: 12500,
            creditLimit: 50000
        )

        let detail = CashbackCardPresentation.pickerDetail(for: card, locale: Locale(identifier: "ru"))

        #expect(detail.contains("Баланс 12 500 RUB"))
        #expect(detail.contains("Лимит 50 000 RUB"))
        #expect(detail.contains("•••• 9876"))
    }

    @Test("Детали карты локализуются для английского и zh-Hans")
    func testDetailUsesRequestedLocale() {
        let card = Card(
            name: "",
            cardNumber: "5555",
            bank: .other,
            cardType: .credit,
            currency: "USD",
            balance: 1200,
            creditLimit: 5000
        )

        let english = CashbackCardPresentation.detail(for: card, locale: Locale(identifier: "en"))
        let chinese = CashbackCardPresentation.detail(for: card, locale: Locale(identifier: "zh-Hans"))
        let chineseTitle = CashbackCardPresentation.title(for: card, locale: Locale(identifier: "zh-Hans"))

        #expect(english.contains("Balance 1 200 USD"))
        #expect(english.contains("Limit 5 000 USD"))
        #expect(chinese.contains("余额 1 200 USD"))
        #expect(chinese.contains("额度 5 000 USD"))
        #expect(chineseTitle == "未命名卡片")
    }

    @Test("Если банк не задан, подзаголовок не засоряется other")
    func testSubtitleSkipsOtherBank() {
        let card = Card(
            name: "Free Card",
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            currency: "USD",
            balance: 0
        )

        let subtitle = CashbackCardPresentation.subtitle(for: card)

        #expect(!subtitle.contains(card.bank.displayName))
        #expect(subtitle == card.cardType.displayName)
    }

    @Test("Если банк не задан, picker подзаголовок показывает только тип")
    func testPickerSubtitleSkipsOtherBank() {
        let card = Card(
            name: "Free Card",
            cardNumber: "",
            bank: .other,
            cardType: .debit,
            currency: "USD",
            balance: 0
        )

        let subtitle = CashbackCardPresentation.pickerSubtitle(for: card)

        #expect(subtitle == card.cardType.displayName)
    }
}
