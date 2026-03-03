import Foundation
import Testing
@testable import millio

@Suite(.serialized)
struct SettingsAndCurrencyDefaultsTests {
    @Test("SettingsManager isBackupEnabled defaults to false")
    func testBackupEnabledDefaultFalse() {
        let key = "isBackupEnabled"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.isBackupEnabled == false)
    }
    
    @Test("SettingsManager isEncryptionEnabled defaults to false")
    func testEncryptionEnabledDefaultFalse() {
        let key = "isEncryptionEnabled"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.isEncryptionEnabled == false)
    }

    @Test("SettingsManager isAppLockEnabled defaults to false")
    func testAppLockEnabledDefaultFalse() {
        let key = "isAppLockEnabled"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.isAppLockEnabled == false)
    }

    @Test("SettingsManager isBiometricUnlockEnabled defaults to false")
    func testBiometricUnlockEnabledDefaultFalse() {
        let key = "isBiometricUnlockEnabled"
        let original = UserDefaults.standard.object(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.isBiometricUnlockEnabled == false)
    }

    @Test("SettingsManager primaryCurrencyCode defaults to RUB")
    func testPrimaryCurrencyDefault() {
        let key = "primaryCurrencyCode"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.primaryCurrencyCode == "RUB")
    }
    
    @Test("SettingsManager primaryCurrencyCode persists and normalizes")
    func testPrimaryCurrencyPersistsAndNormalizes() {
        let key = "primaryCurrencyCode"
        let original = UserDefaults.standard.string(forKey: key) ?? "RUB"
        defer { UserDefaults.standard.set(original, forKey: key) }

        SettingsManager.shared.primaryCurrencyCode = " rub "
        #expect(SettingsManager.shared.primaryCurrencyCode == "RUB")
    }
    
    @Test("SettingsManager favoriteCurrencyCodes defaults to currencies excluding primary")
    func testFavoriteCurrencyDefaults() {
        let primaryKey = "primaryCurrencyCode"
        let key = "favoriteCurrencyCodes"
        let originalPrimary = UserDefaults.standard.string(forKey: primaryKey)
        let original = UserDefaults.standard.array(forKey: key) as? [String]
        defer {
            if let originalPrimary {
                UserDefaults.standard.set(originalPrimary, forKey: primaryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: primaryKey)
            }
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        UserDefaults.standard.set("RUB", forKey: primaryKey)
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.favoriteCurrencyCodes == ["USD", "EUR"])
    }
    
    @Test("SettingsManager favoriteCurrencyCodes persists, normalizes, excludes primary and limits to 5")
    func testFavoriteCurrencyPersistsAndNormalizes() {
        let primaryKey = "primaryCurrencyCode"
        let key = "favoriteCurrencyCodes"
        let originalPrimary = UserDefaults.standard.string(forKey: primaryKey)
        let original = UserDefaults.standard.array(forKey: key) as? [String]
        defer {
            if let originalPrimary {
                UserDefaults.standard.set(originalPrimary, forKey: primaryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: primaryKey)
            }
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        SettingsManager.shared.primaryCurrencyCode = "RUB"
        SettingsManager.shared.favoriteCurrencyCodes = [
            " rub ", "usd", "RUB", "", " eur ", "kzt", "gbp", "try", "chf"
        ]
        #expect(SettingsManager.shared.favoriteCurrencyCodes == ["USD", "EUR", "KZT", "GBP", "TRY"])
    }

    @Test("SettingsManager primaryCurrencyCode update keeps previous primary in favorites and excludes new primary")
    func testPrimaryCurrencyUpdateKeepsPreviousPrimaryInFavorites() {
        let primaryKey = "primaryCurrencyCode"
        let favoritesKey = "favoriteCurrencyCodes"
        let originalPrimary = UserDefaults.standard.string(forKey: primaryKey)
        let originalFavorites = UserDefaults.standard.array(forKey: favoritesKey) as? [String]
        defer {
            if let originalPrimary {
                UserDefaults.standard.set(originalPrimary, forKey: primaryKey)
            } else {
                UserDefaults.standard.removeObject(forKey: primaryKey)
            }
            if let originalFavorites {
                UserDefaults.standard.set(originalFavorites, forKey: favoritesKey)
            } else {
                UserDefaults.standard.removeObject(forKey: favoritesKey)
            }
        }

        SettingsManager.shared.primaryCurrencyCode = "RUB"
        SettingsManager.shared.favoriteCurrencyCodes = ["USD", "EUR", "RUB", "KZT"]
        SettingsManager.shared.primaryCurrencyCode = "USD"

        #expect(SettingsManager.shared.favoriteCurrencyCodes == ["RUB", "EUR", "KZT"])
    }

    @Test("SettingsManager profileAvatarFilePath persists")
    func testProfileAvatarPathPersists() {
        let key = "profileAvatarFilePath"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        let expectedPath = "/tmp/millio-tests/avatar.jpg"
        SettingsManager.shared.profileAvatarFilePath = expectedPath
        #expect(SettingsManager.shared.profileAvatarFilePath == expectedPath)
    }

    @Test("SettingsManager profileDisplayName defaults to localized guest")
    func testProfileDisplayNameDefaultIsLocalizedGuest() {
        let key = "profileDisplayName"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.profileDisplayName == SettingsManager.defaultProfileDisplayName)
    }

    @Test("SettingsManager normalizes legacy guest display names")
    func testProfileDisplayNameNormalizesLegacyGuestValues() {
        let key = "profileDisplayName"
        let original = UserDefaults.standard.string(forKey: key)
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }

        for legacyValue in ["Гость", "Guest"] {
            UserDefaults.standard.set(legacyValue, forKey: key)
            #expect(SettingsManager.shared.profileDisplayName == SettingsManager.defaultProfileDisplayName)
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
    
    @Test("CurrencyRateService ignores conv_rate_source and stays on ERAPI")
    @MainActor
    func testCurrencyRateServiceRateSourceIsolation() {
        defer { UserDefaults.standard.removeObject(forKey: "conv_rate_source") }
        
        UserDefaults.standard.set("frankfurter", forKey: "conv_rate_source")
        #expect(CurrencyRateService.shared.rateSource == .erapi)
    }
}
