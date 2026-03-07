import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct SettingsAndCurrencyDefaultsTests {
    private func makeIsolatedSettingsManager() -> (manager: SettingsManager, defaults: UserDefaults, cleanup: () -> Void) {
        let suiteName = "SettingsAndCurrencyDefaultsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let manager = SettingsManager(defaults: defaults)
        let cleanup = {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return (manager, defaults, cleanup)
    }

    @Test("SettingsManager isBackupEnabled defaults to false")
    func testBackupEnabledDefaultFalse() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "isBackupEnabled")
        #expect(isolated.manager.isBackupEnabled == false)
    }
    
    @Test("SettingsManager isEncryptionEnabled defaults to false")
    func testEncryptionEnabledDefaultFalse() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "isEncryptionEnabled")
        #expect(isolated.manager.isEncryptionEnabled == false)
    }

    @Test("SettingsManager isAppLockEnabled defaults to false")
    func testAppLockEnabledDefaultFalse() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "isAppLockEnabled")
        #expect(isolated.manager.isAppLockEnabled == false)
    }

    @Test("SettingsManager isBiometricUnlockEnabled defaults to false")
    func testBiometricUnlockEnabledDefaultFalse() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "isBiometricUnlockEnabled")
        #expect(isolated.manager.isBiometricUnlockEnabled == false)
    }

    @Test("SettingsManager primaryCurrencyCode defaults to RUB")
    func testPrimaryCurrencyDefault() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "primaryCurrencyCode")
        #expect(isolated.manager.primaryCurrencyCode == "RUB")
    }
    
    @Test("SettingsManager primaryCurrencyCode persists and normalizes")
    func testPrimaryCurrencyPersistsAndNormalizes() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.set("RUB", forKey: "primaryCurrencyCode")
        isolated.manager.primaryCurrencyCode = " rub "
        #expect(isolated.manager.primaryCurrencyCode == "RUB")
    }
    
    @Test("SettingsManager favoriteCurrencyCodes defaults to currencies excluding primary")
    func testFavoriteCurrencyDefaults() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.set("RUB", forKey: "primaryCurrencyCode")
        isolated.defaults.removeObject(forKey: "favoriteCurrencyCodes")
        #expect(isolated.manager.favoriteCurrencyCodes == ["USD", "EUR"])
    }
    
    @Test("SettingsManager favoriteCurrencyCodes persists, normalizes, excludes primary and limits to 5")
    func testFavoriteCurrencyPersistsAndNormalizes() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.manager.primaryCurrencyCode = "RUB"
        isolated.manager.favoriteCurrencyCodes = [
            " rub ", "usd", "RUB", "", " eur ", "kzt", "gbp", "try", "chf"
        ]
        #expect(isolated.manager.favoriteCurrencyCodes == ["USD", "EUR", "KZT", "GBP", "TRY"])
    }

    @Test("SettingsManager primaryCurrencyCode update keeps previous primary in favorites and excludes new primary")
    func testPrimaryCurrencyUpdateKeepsPreviousPrimaryInFavorites() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.manager.primaryCurrencyCode = "RUB"
        isolated.manager.favoriteCurrencyCodes = ["USD", "EUR", "RUB", "KZT"]
        isolated.manager.primaryCurrencyCode = "USD"

        #expect(isolated.manager.favoriteCurrencyCodes == ["RUB", "EUR", "KZT"])
    }

    @Test("SettingsManager profileAvatarFilePath persists")
    func testProfileAvatarPathPersists() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        let expectedPath = "/tmp/millio-tests/avatar.jpg"
        isolated.manager.profileAvatarFilePath = expectedPath
        #expect(isolated.manager.profileAvatarFilePath == expectedPath)
    }

    @Test("SettingsManager profileDisplayName defaults to localized guest")
    func testProfileDisplayNameDefaultIsLocalizedGuest() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        isolated.defaults.removeObject(forKey: "profileDisplayName")
        #expect(isolated.manager.profileDisplayName == SettingsManager.defaultProfileDisplayName)
    }

    @Test("SettingsManager normalizes legacy guest display names")
    func testProfileDisplayNameNormalizesLegacyGuestValues() {
        let isolated = makeIsolatedSettingsManager()
        defer { isolated.cleanup() }

        for legacyValue in ["Гость", "Guest"] {
            isolated.defaults.set(legacyValue, forKey: "profileDisplayName")
            #expect(isolated.manager.profileDisplayName == SettingsManager.defaultProfileDisplayName)
        }
    }

    @Test("AppState loads profile avatar path from SettingsManager on init")
    @MainActor
    func testAppStateLoadsProfileAvatarPathFromSettings() {
        let key = "profileAvatarFilePath"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let expectedPath = "/tmp/millio-tests/avatar-on-relaunch.jpg"
        SettingsManager.shared.profileAvatarFilePath = expectedPath

        let appState = AppState()
        #expect(appState.profileAvatarPath == expectedPath)
    }

    @Test("AppState loads app lock flags from SettingsManager on init")
    @MainActor
    func testAppStateLoadsSecurityFlagsFromSettings() {
        let lockKey = "isAppLockEnabled"
        let biometricKey = "isBiometricUnlockEnabled"
        let originalLock = UserDefaults.standard.object(forKey: lockKey)
        let originalBiometric = UserDefaults.standard.object(forKey: biometricKey)
        defer {
            if let originalLock {
                UserDefaults.standard.set(originalLock, forKey: lockKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lockKey)
            }
            if let originalBiometric {
                UserDefaults.standard.set(originalBiometric, forKey: biometricKey)
            } else {
                UserDefaults.standard.removeObject(forKey: biometricKey)
            }
        }

        SettingsManager.shared.isAppLockEnabled = true
        SettingsManager.shared.isBiometricUnlockEnabled = true

        let appState = AppState()
        #expect(appState.isAppLockEnabled == true)
        #expect(appState.isBiometricUnlockEnabled == true)
        #expect(appState.isAppLocked == true)
    }

    @Test("AppState re-localizes default profile name on language change")
    @MainActor
    func testProfileDisplayNameUpdatesOnLanguageChange() {
        let profileKey = "profileDisplayName"
        let languageKey = "selectedLanguage"
        let appleLanguagesKey = "AppleLanguages"

        let originalProfileName = UserDefaults.standard.string(forKey: profileKey)
        let originalLanguage = UserDefaults.standard.string(forKey: languageKey)
        let originalAppleLanguages = UserDefaults.standard.array(forKey: appleLanguagesKey)

        defer {
            if let originalProfileName {
                UserDefaults.standard.set(originalProfileName, forKey: profileKey)
            } else {
                UserDefaults.standard.removeObject(forKey: profileKey)
            }
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
            if let originalAppleLanguages {
                UserDefaults.standard.set(originalAppleLanguages, forKey: appleLanguagesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
            }
            if let originalLanguage, let restored = Language(rawValue: originalLanguage) {
                LanguageManager.shared.setLanguage(restored)
            }
        }

        UserDefaults.standard.set("Guest", forKey: profileKey)
        LanguageManager.shared.setLanguage(.english)

        let appState = AppState()
        #expect(appState.profileDisplayName == "Guest")

        appState.selectedLanguage = .russian
        #expect(appState.profileDisplayName == "Гость")
        #expect(SettingsManager.shared.profileDisplayName == "Гость")
    }

    @Test("AppState refresh token changes on language update")
    @MainActor
    func testLanguageRefreshTokenChangesOnLanguageUpdate() {
        let languageKey = "selectedLanguage"
        let appleLanguagesKey = "AppleLanguages"

        let originalLanguage = UserDefaults.standard.string(forKey: languageKey)
        let originalAppleLanguages = UserDefaults.standard.array(forKey: appleLanguagesKey)

        defer {
            if let originalLanguage {
                UserDefaults.standard.set(originalLanguage, forKey: languageKey)
            } else {
                UserDefaults.standard.removeObject(forKey: languageKey)
            }
            if let originalAppleLanguages {
                UserDefaults.standard.set(originalAppleLanguages, forKey: appleLanguagesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: appleLanguagesKey)
            }
            if let originalLanguage, let restored = Language(rawValue: originalLanguage) {
                LanguageManager.shared.setLanguage(restored)
            }
        }

        let appState = AppState()
        let initialToken = appState.languageRefreshToken
        let nextLanguage: Language = appState.selectedLanguage == .english ? .russian : .english

        appState.selectedLanguage = nextLanguage
        #expect(appState.languageRefreshToken != initialToken)
    }
    
    @Test("CurrencyRateService ignores conv_rate_source and stays on ERAPI")
    @MainActor
    func testCurrencyRateServiceRateSourceIsolation() {
        defer { UserDefaults.standard.removeObject(forKey: "conv_rate_source") }
        
        UserDefaults.standard.set("frankfurter", forKey: "conv_rate_source")
        #expect(CurrencyRateService.shared.rateSource == .erapi)
    }
}
