import Foundation
import Testing
@testable import millio

struct CashflowScheduledPlannerCopyTests {
    @Test("Подсказка для пустой даты зовет добавить прямо в выбранный день")
    func emptyDaySummaryInvitesAdding() {
        let text = CashflowScheduledPlannerCopy.daySummaryText(entryCount: 0)

        #expect(text.localizedCaseInsensitiveContains("add"))
        #expect(text.localizedCaseInsensitiveContains("date"))
    }

    @Test("Подсказка для занятой даты показывает количество и разрешает добавить еще")
    func filledDaySummaryIncludesCountAndAddAction() {
        let text = CashflowScheduledPlannerCopy.daySummaryText(entryCount: 3)

        #expect(text.contains("3"))
        #expect(text.localizedCaseInsensitiveContains("add another"))
    }
}
