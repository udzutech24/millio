import Foundation
import Testing

struct LocalizationKeysTests {
    @Test("Localizable.xcstrings contains Finances accounts section title")
    func financesAccountsSectionTitleKeyExists() throws {
        let json = try xcstringsJSON(
            "millio/Localizable.xcstrings",
            fromTestFilePath: #filePath
        )

        let strings = try #require(json["strings"] as? [String: Any])
        #expect(
            strings["finances.main.accounts_section.title"] != nil,
            "Missing localization key: finances.main.accounts_section.title"
        )
    }

    private func xcstringsJSON(_ relativePath: String, fromTestFilePath: String) throws -> [String: Any] {
        let fileManager = FileManager.default
        var baseURL = URL(fileURLWithPath: fromTestFilePath).deletingLastPathComponent()

        for _ in 0..<8 {
            let sourceURL = baseURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: sourceURL.path) {
                let data = try Data(contentsOf: sourceURL)
                let object = try JSONSerialization.jsonObject(with: data, options: [])
                return try #require(object as? [String: Any])
            }
            baseURL.deleteLastPathComponent()
        }

        throw NSError(
            domain: "LocalizationKeysTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate xcstrings file: \(relativePath)"]
        )
    }
}

