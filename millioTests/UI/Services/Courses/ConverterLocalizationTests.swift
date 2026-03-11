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
}
