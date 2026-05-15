//
//  CashbackLocalizationTests.swift
//  millioTests
//

import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct CashbackLocalizationTests {
    @Test("Явный locale в cashback не протекает через текущий язык приложения")
    func cashbackExplicitLocaleLookupIgnoresCurrentAppLanguage() {
        let previousLanguage = LanguageManager.shared.currentLanguage
        defer { LanguageManager.shared.setLanguage(previousLanguage) }

        LanguageManager.shared.setLanguage(.russian)

        #expect(AppLocalization.string("cashback.category.supermarket", locale: Locale(identifier: "en")) == "Groceries")
        #expect(AppLocalization.string("cashback.category.supermarket", locale: Locale(identifier: "zh-Hans")) == "商超购物")
        #expect(AppLocalization.string("subscription.button.subscribe", locale: Locale(identifier: "zh-Hans")) == "订阅")
        #expect(
            AppLocalization.string("cashback.card_picker.empty.subtitle", locale: Locale(identifier: "en"))
                == "Add a card in %@"
        )
    }

    @Test("Каталог кешбэк-категорий возвращает разные локализованные имена для en, ru и zh-Hans")
    func cashbackCategoriesExposeLocaleSpecificNames() {
        let checks: [CashbackCategory] = [
            .supermarket,
            .education
        ]

        for category in checks {
            let metadata = CashbackCategoryCatalog.metadata(for: category)
            let english = metadata.localizedDisplayName(locale: Locale(identifier: "en"))
            let russian = metadata.localizedDisplayName(locale: Locale(identifier: "ru"))
            let chinese = metadata.localizedDisplayName(locale: Locale(identifier: "zh-Hans"))

            #expect(!english.isEmpty)
            #expect(!russian.isEmpty)
            #expect(!chinese.isEmpty)
            #expect(english != russian)
            #expect(chinese != english)
        }
    }

    @Test("Системные категории кешбэка резолвятся через локализованный каталог")
    func cashbackCategoriesAreLocalized() {
        AppLanguageTestSupport.withLanguage(.simplifiedChinese) {
            let checks: [CashbackCategory] = [
                .allPurchases,
                .gasStation,
                .supermarket,
                .restaurant,
                .other
            ]

            for category in checks {
                let localized = category.displayName
                let expected = CashbackCategoryCatalog.metadata(for: category).localizedDisplayName()
                #expect(localized == expected)
                #expect(!localized.isEmpty)
            }
        }
    }

    @Test("Ошибки импорта cashback используют локализацию")
    func cashbackImportErrorsAreLocalized() {
        AppLanguageTestSupport.withLockedAppLanguage {
            let checks: [(CashbackScreenshotImportError, String)] = [
                (.invalidImage, "cashback.import.error.invalid_image"),
                (.noTextFound, "cashback.import.error.no_text"),
                (.noCashbackLinesFound, "cashback.import.error.no_cashback_lines")
            ]

            for (error, key) in checks {
                let expected = AppLocalization.string(key, locale: AppLocalization.currentAppLocale)
                #expect(error.errorDescription == expected)
                #expect(error.errorDescription != key)
            }
        }
    }

    @Test("Критичные CTA cashback локализованы для zh-Hans без отката в английский")
    func cashbackCriticalChineseCTAsAreLocalized() {
        let locale = Locale(identifier: "zh-Hans")

        let subscribe = AppLocalization.string(
            "subscription.button.subscribe",
            locale: locale,
            fallback: "Subscribe"
        )
        let screenshotLock = CashbackL10n.text(
            "cashback.import.screenshot.pro_only",
            locale: locale,
            fallback: "Screenshot import is available in PRO"
        )

        #expect(subscribe == "订阅")
        #expect(subscribe != "Subscribe")
        #expect(screenshotLock.contains("PRO"))
        #expect(!screenshotLock.contains("Subscribe"))
    }

    @Test("Пустой экран выбора карты использует локализованное имя сервиса Финансы")
    func cardPickerEmptySubtitleUsesLocalizedFinancesServiceName() {
        let english = CashbackL10n.noCardsSubtitle(locale: Locale(identifier: "en"))
        let russian = CashbackL10n.noCardsSubtitle(locale: Locale(identifier: "ru"))
        let chinese = CashbackL10n.noCardsSubtitle(locale: Locale(identifier: "zh-Hans"))

        #expect(english == "Add a card in Finances")
        #expect(russian == "Добавьте карту в «Финансах»")
        #expect(chinese == "请先在“财务”中添加卡片")
    }
}
