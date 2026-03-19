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
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "ru_RU")).contains("Миллио") == false)
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "ru_RU")) == "Управляйте всеми финансами в одном месте")
    }

    @Test("Share promo English copy stays minimal and clean")
    func sharePromoEnglishCopyIsMinimal() {
        #expect(ConverterL10n.sharePromoSubtitle(locale: Locale(identifier: "en_US")) == "Manage all your finances in one place")
        #expect(ConverterL10n.shareMetaLine(
            dateString: "Mar 19 • 07:28",
            baseSummary: "Base: 1 BTC",
            locale: Locale(identifier: "en_US")
        ).contains("Updated"))
    }
}
