//
//  CashbackCardPresentationTests.swift
//  millioTests
//

import Testing
@testable import millio

@Suite
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

        let detail = CashbackCardPresentation.detail(for: card)

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

        let detail = CashbackCardPresentation.pickerDetail(for: card)

        #expect(detail.contains("Баланс 12 500 RUB"))
        #expect(detail.contains("Лимит 50 000 RUB"))
        #expect(detail.contains("•••• 9876"))
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
