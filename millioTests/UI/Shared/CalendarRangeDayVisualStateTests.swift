import Testing
@testable import millio

struct CalendarRangeDayVisualStateTests {
    @Test("Interior dates in a selected range use outlined circles instead of capsules")
    func interiorRangeDatesUseOutlinedCircles() {
        let state = CalendarRangeDayVisualState.make(
            selected: true,
            isStart: false,
            isEnd: false,
            isSingleDay: false,
            highlightsSingleDaySelection: true,
            isToday: false
        )

        #expect(state.showsFilledEdgeCircle == false)
        #expect(state.showsSelectedOutlineCircle)
        #expect(state.showsTodayOutlineCircle == false)
    }

    @Test("Range edges keep the filled circular treatment")
    func rangeEdgesStayFilled() {
        let state = CalendarRangeDayVisualState.make(
            selected: true,
            isStart: true,
            isEnd: false,
            isSingleDay: false,
            highlightsSingleDaySelection: true,
            isToday: false
        )

        #expect(state.showsFilledEdgeCircle)
        #expect(state.showsSelectedOutlineCircle == false)
        #expect(state.showsTodayOutlineCircle == false)
    }

    @Test("Today ring is suppressed when the day is already selected inside the range")
    func todayRingDoesNotCompeteWithSelectedOutline() {
        let state = CalendarRangeDayVisualState.make(
            selected: true,
            isStart: false,
            isEnd: false,
            isSingleDay: false,
            highlightsSingleDaySelection: true,
            isToday: true
        )

        #expect(state.showsSelectedOutlineCircle)
        #expect(state.showsTodayOutlineCircle == false)
    }
}
