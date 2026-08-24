import Foundation
import Testing
@testable import millio

struct BackupLocalizationTests {
    @Test("Backup screen never relies on English fallback for missing catalog keys")
    func testBackupMissingCatalogKeysAreCoveredInline() throws {
        let sourceFiles = [
            "millio/UI/Profile/BackupManagementView.swift",
            "millio/UI/Profile/BackupExperienceModels.swift",
            // R4: экран восстановления — такой же пользовательский текст, ему нужен тот же гейт.
            "millio/UI/Restore/RestoreView.swift",
            "millio/UI/Restore/RestoreErrorPresenter.swift"
        ]

        let usedKeys = try Set(sourceFiles.flatMap(BackupLocalizationTests.backupLocalizationKeys(in:)))
        let strings = try BackupLocalizationTests.xcstringsStringsDictionary()
        let missingCatalogKeys = usedKeys.subtracting(strings.keys)

        for key in missingCatalogKeys.sorted() {
            #expect(BackupL10n.hasInlineTranslation(for: key), "Missing inline backup localization for key: \(key)")
        }
    }

    @Test("Backup inline translations resolve for Russian and Simplified Chinese")
    func testBackupInlineTranslationsResolveForReleaseLanguages() {
        let ruLocale = Locale(identifier: "ru_RU")
        let zhLocale = Locale(identifier: "zh_Hans_CN")

        #expect(BackupL10n.tr("backup.dashboard.title.off", locale: ruLocale, fallback: "fallback") == "Данные пока только локально")
        #expect(BackupL10n.tr("backup.dashboard.title.off", locale: zhLocale, fallback: "fallback") == "你的数据目前只在本机")
        #expect(BackupL10n.tr("backup.passphrase.save", locale: ruLocale, fallback: "fallback") == "Сохранить кодовую фразу")
        #expect(BackupL10n.tr("backup.passphrase.save", locale: zhLocale, fallback: "fallback") == "保存口令短语")
        #expect(BackupL10n.tr("common.done", locale: ruLocale, fallback: "fallback") == "Готово")
        #expect(BackupL10n.tr("common.done", locale: zhLocale, fallback: "fallback") == "完成")
    }

    @Test("Backup copy falls back to English for unsupported locales")
    func testBackupInlineTranslationsFallbackToEnglishForUnsupportedLocale() {
        let french = Locale(identifier: "fr_FR")

        #expect(
            BackupL10n.tr("backup.hint.enable_backup", locale: french, fallback: "fallback")
                == "Enable backup"
        )
    }

    private static func backupLocalizationKeys(in relativePath: String) throws -> [String] {
        let fileURL = try sourceURL(for: relativePath)
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        let pattern = #"BackupL10n\.(?:tr|format)\("([^"]+)""#
        let regex = try NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(source.startIndex..<source.endIndex, in: source)

        return regex.matches(in: source, range: nsRange).compactMap { match in
            guard
                match.numberOfRanges > 1,
                let range = Range(match.range(at: 1), in: source)
            else {
                return nil
            }

            return String(source[range])
        }
    }

    private static func xcstringsStringsDictionary() throws -> [String: Any] {
        let json = try xcstringsJSON("millio/Localizable.xcstrings")
        return try #require(json["strings"] as? [String: Any])
    }

    private static func xcstringsJSON(_ relativePath: String) throws -> [String: Any] {
        let fileURL = try sourceURL(for: relativePath)
        let data = try Data(contentsOf: fileURL)
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        return try #require(object as? [String: Any])
    }

    private static func sourceURL(for relativePath: String) throws -> URL {
        let fileManager = FileManager.default
        var baseURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        for _ in 0..<8 {
            let candidate = baseURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
            baseURL.deleteLastPathComponent()
        }

        throw NSError(
            domain: "BackupLocalizationTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate source file: \(relativePath)"]
        )
    }
}
