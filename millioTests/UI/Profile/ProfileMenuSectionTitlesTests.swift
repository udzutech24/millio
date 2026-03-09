import Foundation
import Testing
@testable import millio

@Suite("Profile section titles")
struct ProfileMenuSectionTitlesTests {
    @Test("Each section has a stable localization key")
    func testLocalizationKeys() {
        #expect(ProfileMenuSectionID.general.localizationKey == "profile.section.general")
        #expect(ProfileMenuSectionID.settings.localizationKey == "profile.section.settings")
        #expect(ProfileMenuSectionID.experience.localizationKey == "profile.section.experience")
        #expect(ProfileMenuSectionID.support.localizationKey == "profile.section.support")
        #expect(ProfileMenuSectionID.about.localizationKey == "profile.section.about")
        #expect(ProfileMenuSectionID.contacts.localizationKey == "profile.section.contacts")
        #expect(ProfileMenuSectionID.debug.localizationKey == "profile.section.debug")
    }

    @Test("Fallback titles are user-readable labels")
    func testFallbackTitlesAreReadable() {
        for section in ProfileMenuSectionID.allCases {
            #expect(!section.fallbackTitle.isEmpty)
            #expect(!section.fallbackTitle.contains("profile.section."))
        }
    }
}

private extension ProfileMenuSectionID {
    static var allCases: [ProfileMenuSectionID] {
        [.general, .settings, .experience, .support, .about, .contacts, .debug]
    }
}
