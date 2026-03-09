import Foundation
import Testing
@testable import millio

@Suite("Profile menu structure")
struct ProfileMenuStructureTests {
    @Test("Settings keeps only actual settings")
    func testSettingsSectionContainsOnlySettings() throws {
        let settingsSection = try #require(ProfileMenuStructure.sections.first { $0.id == .settings })

        #expect(settingsSection.items == [.backup, .security, .dailyReminders])
    }

    @Test("Moved items live outside settings")
    func testMovedItemsAreSeparatedFromSettings() throws {
        let settingsSection = try #require(ProfileMenuStructure.sections.first { $0.id == .settings })
        let experienceSection = try #require(ProfileMenuStructure.sections.first { $0.id == .experience })
        let supportSection = try #require(ProfileMenuStructure.sections.first { $0.id == .support })

        #expect(!settingsSection.items.contains(.faq))
        #expect(!settingsSection.items.contains(.quickSetup))
        #expect(!settingsSection.items.contains(.launchSplash))
        #expect(!settingsSection.items.contains(.smartDataReset))

        #expect(experienceSection.items == [.quickSetup, .launchSplash])
        #expect(supportSection.items == [.faq, .smartDataReset])
    }

    @Test("Section order follows Apple-style scan path")
    func testSectionOrder() {
        let order = ProfileMenuStructure.sections.map(\.id)

        #expect(order == [.general, .settings, .experience, .support, .about, .debug, .contacts])
    }

    @Test("Contacts section includes only support entry")
    func testContactsSectionItems() throws {
        let contactsSection = try #require(ProfileMenuStructure.sections.first { $0.id == .contacts })

        #expect(contactsSection.items == [.contactUs])
    }
}
