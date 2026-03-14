import Foundation
import Testing
@testable import millio

struct CashflowScheduledPlannerCopyTests {
    @Test("Подсказка для пустой даты зовет добавить прямо в выбранный день")
    func emptyDaySummaryInvitesAdding() {
        let text = CashflowScheduledPlannerCopy.daySummaryText(
            entryCount: 0,
            locale: Locale(identifier: "en_US")
        )

        #expect(text.localizedCaseInsensitiveContains("add"))
        #expect(text.localizedCaseInsensitiveContains("date"))
    }

    @Test("Подсказка для занятой даты показывает количество и разрешает добавить еще")
    func filledDaySummaryIncludesCountAndAddAction() {
        let text = CashflowScheduledPlannerCopy.daySummaryText(
            entryCount: 3,
            locale: Locale(identifier: "en_US")
        )

        #expect(text.contains("3"))
        #expect(text.localizedCaseInsensitiveContains("add another"))
    }

    @Test("Подсказка для пустой даты локализуется на русский")
    func emptyDaySummaryLocalizesToRussian() {
        let text = CashflowScheduledPlannerCopy.daySummaryText(
            entryCount: 0,
            locale: Locale(identifier: "ru_RU")
        )

        #expect(text.localizedCaseInsensitiveContains("добав"))
        #expect(text.localizedCaseInsensitiveContains("дат"))
    }
}
