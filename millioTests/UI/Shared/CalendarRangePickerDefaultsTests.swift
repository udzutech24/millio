import Testing
@testable import millio

struct CalendarRangePickerDefaultsTests {
    @Test("Custom range picker starts by selecting the start date")
    func initialEndpointDefaultsToStartDate() {
        #expect(CalendarRangePickerDefaults.initialEndpoint == .start)
    }
}
