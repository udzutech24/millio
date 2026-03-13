import Testing
@testable import millio

struct BackendDebugStatusContentTests {
    @Test("builds visible backend banner content for auth screen")
    func testMakeBuildsContent() {
        let content = BackendDebugStatusContent.make(
            regionCode: "de",
            baseURLString: "https://api.udzutech.com/api/v1",
            isFallbackActive: false
        )

        #expect(content?.regionLine == "Login backend: DE")
        #expect(content?.baseURLLine == "https://api.udzutech.com/api/v1")
        #expect(content?.fallbackLine == "Fallback: off")
    }

    @Test("skips backend banner when runtime base URL is empty")
    func testMakeReturnsNilForEmptyBaseURL() {
        let content = BackendDebugStatusContent.make(
            regionCode: "RU",
            baseURLString: "   ",
            isFallbackActive: true
        )

        #expect(content == nil)
    }
}
