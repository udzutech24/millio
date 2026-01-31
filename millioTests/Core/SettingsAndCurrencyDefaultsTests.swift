import Foundation
import Testing
@testable import millio

struct SettingsAndCurrencyDefaultsTests {
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
    
    @Test("CurrencyRateService ignores conv_rate_source and stays on ERAPI")
    @MainActor
    func testCurrencyRateServiceRateSourceIsolation() {
        defer { UserDefaults.standard.removeObject(forKey: "conv_rate_source") }
        
        UserDefaults.standard.set("frankfurter", forKey: "conv_rate_source")
        #expect(CurrencyRateService.shared.rateSource == .erapi)
    }
}
