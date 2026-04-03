import Foundation

enum ProfileAuthL10n {
    static func connectedTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.connected",
            locale: locale,
            fallback: "Signed in with Apple"
        )
    }

    static func connectedSubtitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.connected.subtitle",
            locale: locale,
            fallback: "Account sync is enabled for this account. iCloud backup uses the current Apple account on this device."
        )
    }

    static func emailMissingTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.email_missing",
            locale: locale,
            fallback: "No email provided"
        )
    }

    static func guestTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.guest.title",
            locale: locale,
            fallback: "Guest Mode"
        )
    }

    static func guestSubtitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.guest.subtitle",
            locale: locale,
            fallback: "Use Millio now and connect your Apple Account later."
        )
    }

    static func exitGuestTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.exit_guest",
            locale: locale,
            fallback: "Leave Guest Mode"
        )
    }

    static func detailsTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.details",
            locale: locale,
            fallback: "View details"
        )
    }

    static func notSignedInTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.not_signed_in",
            locale: locale,
            fallback: "Not signed in"
        )
    }

    static func notSignedInSubtitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.not_signed_in.subtitle",
            locale: locale,
            fallback: "Sign in with Apple to enable account sync. iCloud backup works separately."
        )
    }

    static func accountDetailsTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.account_details",
            locale: locale,
            fallback: "Account details"
        )
    }

    static func logoutTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.logout",
            locale: locale,
            fallback: "Sign out"
        )
    }

    static func nameTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.name",
            locale: locale,
            fallback: "Name"
        )
    }

    static func emailTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.email",
            locale: locale,
            fallback: "Email"
        )
    }

    static func lastLoginTitle(locale: Locale = AppLocalization.currentAppLocale) -> String {
        AppLocalization.string(
            "profile.auth.last_login",
            locale: locale,
            fallback: "Last sign-in"
        )
    }
}
