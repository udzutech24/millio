import Foundation
import Testing
@testable import millio

@Suite("Profile display name resolver")
struct ProfileDisplayNameResolverTests {
    @Test("Header uses custom stored name when it is not guest default")
    func testHeaderUsesCustomStoredName() {
        let user = AuthUser(
            id: "u1",
            email: "a@example.com",
            emailVerified: true,
            firstName: "Aleksey",
            lastName: "A",
            fullName: "Aleksey A",
            avatarUrl: nil,
            lastLoginAt: nil
        )

        let value = ProfileDisplayNameResolver.headerDisplayName(
            storedDisplayName: "My Custom Name",
            authUser: user
        )

        #expect(value == "My Custom Name")
    }

    @Test("Header uses Apple full name when stored value is guest default")
    func testHeaderUsesAppleFullNameForGuestStoredValue() {
        let user = AuthUser(
            id: "u1",
            email: "a@example.com",
            emailVerified: true,
            firstName: "Aleksey",
            lastName: "A",
            fullName: "Aleksey A",
            avatarUrl: nil,
            lastLoginAt: nil
        )

        let value = ProfileDisplayNameResolver.headerDisplayName(
            storedDisplayName: "Guest",
            authUser: user
        )

        #expect(value == "Aleksey A")
    }

    @Test("Header falls back to first and last name when full name is missing")
    func testHeaderFallsBackToFirstAndLastName() {
        let user = AuthUser(
            id: "u1",
            email: "a@example.com",
            emailVerified: true,
            firstName: "Aleksey",
            lastName: "A",
            fullName: nil,
            avatarUrl: nil,
            lastLoginAt: nil
        )

        let value = ProfileDisplayNameResolver.headerDisplayName(
            storedDisplayName: "Guest",
            authUser: user
        )

        #expect(value == "Aleksey A")
    }

    @Test("Header keeps localized guest value when no user name exists")
    func testHeaderFallsBackToLocalizedGuest() {
        let user = AuthUser(
            id: "u1",
            email: "a@example.com",
            emailVerified: true,
            firstName: nil,
            lastName: nil,
            fullName: nil,
            avatarUrl: nil,
            lastLoginAt: nil
        )

        let value = ProfileDisplayNameResolver.headerDisplayName(
            storedDisplayName: "Guest",
            authUser: user
        )

        #expect(value == SettingsManager.defaultProfileDisplayName)
    }
}
