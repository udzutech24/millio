import Foundation
import Testing
@testable import millio

struct ConverterLocalizationTests {

    @Test("Converter share title uses localized numbered format")
    func shareTitleContainsSequenceNumber() {
        let title = ConverterL10n.shareTitle(index: 7)
        #expect(title.contains("7"))
        #expect(!title.isEmpty)
    }

    @Test("Converter share title format resolves explicit locale variants")
    func shareTitleUsesLocalizedFormatPerLocale() {
        let english = String(
            format: AppLocalization.string(
                "converter.share.title_format",
                locale: Locale(identifier: "en")
            ),
            locale: Locale(identifier: "en"),
            7
        )
        let russian = String(
            format: AppLocalization.string(
                "converter.share.title_format",
                locale: Locale(identifier: "ru")
            ),
            locale: Locale(identifier: "ru"),
            7
        )

        #expect(english == "Snapshot #7")
        #expect(russian == "Отправка #7")
    }

    @Test("Converter error templates inject rate source")
    func errorTemplatesInjectSourceName() {
        let source = "Frankfurter"
        #expect(ConverterL10n.serverError(source: source).contains(source))
        #expect(ConverterL10n.parseError(source: source).contains(source))
    }

    @Test("Rate source subtitles are localized and non-empty")
    func rateSourceSubtitlesArePresent() {
        for source in RateSource.allCases {
            #expect(!source.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("Widget settings copy is localized and non-empty")
    func widgetSettingsCopyIsPresent() {
        let values = [
            ConverterL10n.sectionWidget,
            ConverterL10n.widgetPreviewTitle,
            ConverterL10n.widgetPreviewSubtitle,
            ConverterL10n.widgetHowToTitle,
            ConverterL10n.widgetStepOpenJiggle,
            ConverterL10n.widgetStepFindMillio,
            ConverterL10n.widgetStepAddWidget
        ]

        for value in values {
            #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("Share promo brand stays millio in Russian locale")
    func sharePromoBrandDoesNotLocalizeAppName() {
        #expect(ConverterL10n.sharePromoBrand == "millio")
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "ru_RU")) == "Снято в приложении Миллио")
    }

    @Test("Share promo copy resolves through locale-aware contract")
    func sharePromoCopyUsesLocaleAwareContract() {
        #expect(ConverterL10n.sharePromoTitle(locale: Locale(identifier: "en_US")) == "Smarter money decisions, faster")
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "en_US")) == "Built with Millio")
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "zh-Hans")) == "来自 Millio")
        #expect(ConverterL10n.shareMetaLine(
            dateString: "Mar 19 • 07:28",
            baseSummary: "Base: 1 BTC",
            locale: Locale(identifier: "en_US")
        ).contains("Updated"))
        #expect(ConverterL10n.shareMetaLine(
            dateString: "19 мар. • 07:28",
            baseSummary: "База: 1 BTC",
            locale: Locale(identifier: "ru_RU")
        ).contains("Обновлено"))
        #expect(ConverterL10n.shareMetaLine(
            dateString: "3月19日 • 07:28",
            baseSummary: "Base: 1 BTC",
            locale: Locale(identifier: "zh-Hans")
        ).contains("已更新"))
    }
}
