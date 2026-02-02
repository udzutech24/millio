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
    
    @Test("SettingsManager favoriteCurrencyCodes defaults to RUB/USD/EUR")
    func testFavoriteCurrencyDefaults() {
        let key = "favoriteCurrencyCodes"
        let original = UserDefaults.standard.array(forKey: key) as? [String]
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        UserDefaults.standard.removeObject(forKey: key)
        #expect(SettingsManager.shared.favoriteCurrencyCodes == ["RUB", "USD", "EUR"])
    }
    
    @Test("SettingsManager favoriteCurrencyCodes persists and normalizes uniquely")
    func testFavoriteCurrencyPersistsAndNormalizes() {
        let key = "favoriteCurrencyCodes"
        let original = UserDefaults.standard.array(forKey: key) as? [String]
        defer {
            if let original {
                UserDefaults.standard.set(original, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        
        SettingsManager.shared.favoriteCurrencyCodes = [" rub ", "usd", "RUB", "", " eur "]
        #expect(SettingsManager.shared.favoriteCurrencyCodes == ["RUB", "USD", "EUR"])
    }
    
    @Test("CurrencyRateService ignores conv_rate_source and stays on ERAPI")
    @MainActor
    func testCurrencyRateServiceRateSourceIsolation() {
        defer { UserDefaults.standard.removeObject(forKey: "conv_rate_source") }
        
        UserDefaults.standard.set("frankfurter", forKey: "conv_rate_source")
        #expect(CurrencyRateService.shared.rateSource == .erapi)
    }
}
