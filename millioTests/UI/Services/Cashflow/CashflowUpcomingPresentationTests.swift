import Foundation
import Testing
@testable import millio

@Suite("CashflowUpcomingPresentation")
struct CashflowUpcomingPresentationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private func item(id: String, day: Int, hour: Int, kind: CashflowCategoryKind) -> CashflowUpcomingItem {
        CashflowUpcomingItem(
            id: id,
            date: calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!,
            kind: kind,
            title: id,
            categoryTitle: "Category",
            source: .oneTimePlanned,
            reference: .deposit(accountID: UUID()),
            amount: 100,
            currencyCode: id == "usd" ? "USD" : "RUB"
        )
    }

    @Test("All groups mixed directions chronologically by calendar day")
    func allGroupsAndSorts() {
        let sections = CashflowUpcomingPresentation.sections(
            from: [item(id: "late", day: 16, hour: 9, kind: .expense),
                   item(id: "early", day: 15, hour: 8, kind: .income),
                   item(id: "same-day", day: 15, hour: 12, kind: .expense)],
            filter: .all,
            calendar: calendar
        )
        #expect(sections.count == 2)
        #expect(sections[0].items.map(\.id) == ["early", "same-day"])
        #expect(sections[1].items.map(\.id) == ["late"])
    }

    @Test("Income and expense filters only change presentation")
    func filtersDirections() {
        let source = [item(id: "income", day: 15, hour: 8, kind: .income),
                      item(id: "expense", day: 15, hour: 9, kind: .expense)]
        let income = CashflowUpcomingPresentation.sections(from: source, filter: .income, calendar: calendar)
        let expenses = CashflowUpcomingPresentation.sections(from: source, filter: .expenses, calendar: calendar)
        #expect(income.flatMap(\.items).map(\.id) == ["income"])
        #expect(expenses.flatMap(\.items).map(\.id) == ["expense"])
        #expect(source.count == 2)
    }

    @Test("Прогноз вклада резолвит точный активный счёт")
    func depositAccountResolution() throws {
        let target = Account(name: "Target", kind: .deposit, currency: "RUB")
        let other = Account(name: "Other", kind: .deposit, currency: "RUB")
        #expect(CashflowUpcomingAccountResolver.resolve(accountID: target.id, in: [other, target]) === target)
        target.deletedAt = Date()
        #expect(CashflowUpcomingAccountResolver.resolve(accountID: target.id, in: [other, target]) == nil)
    }
}
