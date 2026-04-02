import Foundation
@testable import millio

enum AppLanguageTestSupport {
    static func withLockedAppLanguage<T>(_ test: () throws -> T) rethrows -> T {
        try LanguageManager.withLockedLanguageMutation(test)
    }

    static func withLanguage<T>(_ language: Language, test: () throws -> T) rethrows -> T {
        try withLockedAppLanguage {
            let previousLanguage = LanguageManager.shared.currentLanguage
            LanguageManager.shared.setLanguage(language)

            defer {
                LanguageManager.shared.setLanguage(previousLanguage)
            }

            return try test()
        }
    }
}
