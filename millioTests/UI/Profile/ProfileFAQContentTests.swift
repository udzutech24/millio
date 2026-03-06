import Foundation
import Testing
@testable import millio

@Suite("Profile FAQ content")
struct ProfileFAQContentTests {
    @Test("FAQ has non-empty sections and items for English")
    func testEnglishFAQHasContent() {
        let sections = ProfileFAQContent.sections(for: .english)

        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { !$0.items.isEmpty })
        #expect(sections.flatMap(\.items).allSatisfy { !$0.question.isEmpty })
        #expect(sections.flatMap(\.items).allSatisfy { !$0.answerParagraphs.isEmpty })
    }

    @Test("FAQ has non-empty sections and items for Russian")
    func testRussianFAQHasContent() {
        let sections = ProfileFAQContent.sections(for: .russian)

        #expect(!sections.isEmpty)
        #expect(sections.allSatisfy { !$0.items.isEmpty })
        #expect(sections.flatMap(\.items).allSatisfy { !$0.question.isEmpty })
        #expect(sections.flatMap(\.items).allSatisfy { !$0.answerParagraphs.isEmpty })
    }

    @Test("FAQ item ids are unique inside each localization")
    func testFAQItemIDsAreUnique() {
        let englishIDs = ProfileFAQContent.sections(for: .english).flatMap(\.items).map(\.id)
        let russianIDs = ProfileFAQContent.sections(for: .russian).flatMap(\.items).map(\.id)

        #expect(Set(englishIDs).count == englishIDs.count)
        #expect(Set(russianIDs).count == russianIDs.count)
    }
}
