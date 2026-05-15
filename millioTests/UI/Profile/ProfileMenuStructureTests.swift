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
        #expect(supportSection.items == [.faq])
    }

    @Test("Section order follows Apple-style scan path")
    func testSectionOrder() {
        let order = ProfileMenuStructure.sections.map(\.id)

#if DEBUG
        #expect(order == [.general, .settings, .experience, .support, .about, .debug, .contacts])
#else
        #expect(order == [.general, .settings, .experience, .support, .about, .contacts])
#endif
    }

    @Test("Contacts section includes only support entry")
    func testContactsSectionItems() throws {
        let contactsSection = try #require(ProfileMenuStructure.sections.first { $0.id == .contacts })

        #expect(contactsSection.items == [.contactUs])
    }

    @Test("Profile menu items keep stable icon styling semantics")
    func testProfileMenuIconMetadata() {
        #expect(ProfileMenuItemID.language.iconSystemName == "globe")
        #expect(ProfileMenuItemID.language.iconTone == .blue)
        #expect(ProfileMenuItemID.primaryCurrency.iconTone == .green)
        #expect(ProfileMenuItemID.backup.iconTone == .cyan)
        #expect(ProfileMenuItemID.dailyReminders.iconTone == .orange)
        #expect(ProfileMenuItemID.quickSetup.iconTone == .purple)
        #expect(ProfileMenuItemID.launchSplash.iconTone == .pink)
        #expect(ProfileMenuItemID.smartDataReset.iconTone == .red)
        #expect(ProfileMenuItemID.version.iconTone == .cyan)
        #expect(ProfileMenuItemID.privacy.iconTone == .orange)
        #expect(ProfileMenuItemID.terms.iconTone == .blue)
        #expect(ProfileMenuItemID.contactUs.iconTone == .teal)
#if DEBUG
        #expect(ProfileMenuItemID.adminStats.iconSystemName == "chart.bar.xaxis")
        #expect(ProfileMenuItemID.adminStats.iconTone == .teal)
#endif
    }

    @Test("Debug section is available only in debug builds")
    func testDebugSectionItems() throws {
#if DEBUG
        let debugSection = try #require(ProfileMenuStructure.sections.first { $0.id == .debug })
        #expect(debugSection.items == [.premiumAccess, .trialDisabled, .premiumDiagnostics, .showOnboarding, .smartDataReset, .adminStats])
#else
        #expect(ProfileMenuStructure.sections.contains { $0.id == .debug } == false)
#endif
    }
}
