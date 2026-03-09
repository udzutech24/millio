import Foundation
import Testing

struct LocalizationHotReloadTests {
    @Test("Converter localization entries are not cached in static let")
    func converterLocalizationIsNotCached() throws {
        let source = try sourceFile(
            "millio/UI/Services/Courses/ConverterLocalization.swift",
            fromTestFilePath: #filePath
        )
        #expect(
            !source.contains("static let") || !source.contains("String(localized:"),
            "Do not cache localized strings with static let in ConverterL10n. Use computed properties."
        )
    }

    @Test("Converter share preview title is localized (no hardcoded Russian)")
    func converterSharePreviewTitleIsLocalized() throws {
        let source = try sourceFile(
            "millio/UI/Services/Courses/ConverterView.swift",
            fromTestFilePath: #filePath
        )
        #expect(
            !source.contains("\"предусмотр\""),
            "Do not hardcode Russian UI strings in ConverterView. Use ConverterL10n.sharePreviewTitle."
        )
    }

    @Test("Courses title uses localization key (no hardcoded Russian)")
    func coursesTitleUsesLocalizationKey() throws {
        let source = try sourceFile(
            "millio/UI/Services/Courses/CoursesView.swift",
            fromTestFilePath: #filePath
        )
        #expect(
            !source.contains("\"Курсы\""),
            "Do not hardcode Russian UI strings in CoursesView. Use MainLocalization.serviceCourses."
        )
        #expect(
            source.contains("MainLocalization.serviceCourses"),
            "CoursesView should use MainLocalization.serviceCourses for the title."
        )
    }

    @Test("Finance ungrouped group name is resolved dynamically")
    func financeUngroupedNameIsDynamic() throws {
        let source = try sourceFile(
            "millio/UI/Services/Finances/FinanceViewModel.swift",
            fromTestFilePath: #filePath
        )
        #expect(
            !source.contains("private let ungroupedGroupName = String(localized:"),
            "Ungrouped group localization should not be cached in a let property."
        )
    }

    private func sourceFile(_ relativePath: String, fromTestFilePath: String) throws -> String {
        let fileManager = FileManager.default
        var baseURL = URL(fileURLWithPath: fromTestFilePath).deletingLastPathComponent()

        for _ in 0..<8 {
            let sourceURL = baseURL.appendingPathComponent(relativePath)
            if fileManager.fileExists(atPath: sourceURL.path) {
                return try String(contentsOf: sourceURL, encoding: .utf8)
            }
            baseURL.deleteLastPathComponent()
        }

        throw NSError(
            domain: "LocalizationHotReloadTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unable to locate source file: \(relativePath)"]
        )
    }
}
