import Foundation
import Testing
@testable import millio

struct CalendarRangeSelectionLogicTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("Endpoint mode advances from start selection to end selection")
    func endpointModeAdvancesAfterChoosingStart() {
        let start = makeDate(year: 2026, month: 3, day: 3)
        let end = makeDate(year: 2026, month: 3, day: 10)
        let tapped = makeDate(year: 2026, month: 3, day: 5)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tapped,
            startDate: start,
            endDate: end,
            activeEndpoint: .start,
            calendar: calendar
        )

        #expect(result.startDate == tapped)
        #expect(result.endDate == end)
        #expect(result.nextEndpoint == .end)
    }

    @Test("Endpoint mode clamps end to start when user chooses a later start date")
    func endpointModeKeepsRangeValidWhenStartMovesPastEnd() {
        let start = makeDate(year: 2026, month: 3, day: 3)
        let end = makeDate(year: 2026, month: 3, day: 10)
        let tapped = makeDate(year: 2026, month: 3, day: 15)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tapped,
            startDate: start,
            endDate: end,
            activeEndpoint: .start,
            calendar: calendar
        )

        #expect(result.startDate == tapped)
        #expect(result.endDate == tapped)
        #expect(result.nextEndpoint == .end)
    }

    @Test("Endpoint mode clamps start to end when user chooses an earlier end date")
    func endpointModeKeepsRangeValidWhenEndMovesBeforeStart() {
        let start = makeDate(year: 2026, month: 3, day: 10)
        let end = makeDate(year: 2026, month: 3, day: 15)
        let tapped = makeDate(year: 2026, month: 3, day: 5)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tapped,
            startDate: start,
            endDate: end,
            activeEndpoint: .end,
            calendar: calendar
        )

        #expect(result.startDate == tapped)
        #expect(result.endDate == tapped)
        #expect(result.nextEndpoint == .start)
    }

    @Test("Legacy mode expands a single-day selection into a range on the second tap")
    func legacyModeStillSupportsTwoTapRangeSelection() {
        let start = makeDate(year: 2026, month: 3, day: 3)
        let tapped = makeDate(year: 2026, month: 3, day: 9)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tapped,
            startDate: start,
            endDate: start,
            activeEndpoint: nil,
            calendar: calendar
        )

        #expect(result.startDate == start)
        #expect(result.endDate == tapped)
        #expect(result.nextEndpoint == nil)
    }

    @Test("Endpoint flow keeps the chosen start date when user then picks a later end date")
    func endpointFlowPreservesChosenStartWhenSelectingLaterEnd() {
        let initial = makeDate(year: 2026, month: 3, day: 7)
        let chosenStart = makeDate(year: 2026, month: 3, day: 3)
        let chosenEnd = makeDate(year: 2026, month: 3, day: 22)

        let afterChoosingStart = CalendarRangeSelectionLogic.applyTap(
            on: chosenStart,
            startDate: initial,
            endDate: initial,
            activeEndpoint: .start,
            calendar: calendar
        )

        let afterChoosingEnd = CalendarRangeSelectionLogic.applyTap(
            on: chosenEnd,
            startDate: afterChoosingStart.startDate,
            endDate: afterChoosingStart.endDate,
            activeEndpoint: .end,
            calendar: calendar
        )

        #expect(afterChoosingStart.startDate == chosenStart)
        #expect(afterChoosingStart.endDate == initial)
        #expect(afterChoosingStart.nextEndpoint == .end)
        #expect(afterChoosingEnd.startDate == chosenStart)
        #expect(afterChoosingEnd.endDate == chosenEnd)
        #expect(afterChoosingEnd.nextEndpoint == .start)
    }

    @Test("Endpoint flow supports choosing end date before start date")
    func endpointFlowSupportsChoosingEndDateFirst() {
        let initial = makeDate(year: 2026, month: 3, day: 7)
        let chosenEnd = makeDate(year: 2026, month: 3, day: 22)
        let chosenStart = makeDate(year: 2026, month: 3, day: 3)

        let afterChoosingEnd = CalendarRangeSelectionLogic.applyTap(
            on: chosenEnd,
            startDate: initial,
            endDate: initial,
            activeEndpoint: .end,
            calendar: calendar
        )

        let afterChoosingStart = CalendarRangeSelectionLogic.applyTap(
            on: chosenStart,
            startDate: afterChoosingEnd.startDate,
            endDate: afterChoosingEnd.endDate,
            activeEndpoint: .start,
            calendar: calendar
        )

        #expect(afterChoosingEnd.startDate == initial)
        #expect(afterChoosingEnd.endDate == chosenEnd)
        #expect(afterChoosingEnd.nextEndpoint == .start)
        #expect(afterChoosingStart.startDate == chosenStart)
        #expect(afterChoosingStart.endDate == chosenEnd)
        #expect(afterChoosingStart.nextEndpoint == .end)
    }

    @Test("Single-day selection expands backward instead of collapsing when end endpoint is active")
    func singleDaySelectionExpandsBackwardFromActiveEnd() {
        let singleDay = makeDate(year: 2026, month: 2, day: 13)
        let tappedEarlier = makeDate(year: 2026, month: 2, day: 11)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tappedEarlier,
            startDate: singleDay,
            endDate: singleDay,
            activeEndpoint: .end,
            calendar: calendar
        )

        #expect(result.startDate == tappedEarlier)
        #expect(result.endDate == singleDay)
        #expect(result.nextEndpoint == .end)
    }

    @Test("Single-day selection expands forward instead of collapsing when start endpoint is active")
    func singleDaySelectionExpandsForwardFromActiveStart() {
        let singleDay = makeDate(year: 2026, month: 2, day: 13)
        let tappedLater = makeDate(year: 2026, month: 2, day: 14)

        let result = CalendarRangeSelectionLogic.applyTap(
            on: tappedLater,
            startDate: singleDay,
            endDate: singleDay,
            activeEndpoint: .start,
            calendar: calendar
        )

        #expect(result.startDate == singleDay)
        #expect(result.endDate == tappedLater)
        #expect(result.nextEndpoint == .start)
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
