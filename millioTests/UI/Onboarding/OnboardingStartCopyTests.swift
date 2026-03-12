import XCTest
@testable import millio

final class OnboardingStartCopyTests: XCTestCase {
    func testRussianCopyUsesIndustrialTone() {
        let locale = Locale(identifier: "ru_RU")

        XCTAssertEqual(OnboardingStartCopy.badge(locale: locale), "ПУСКОВОЙ ПРОТОКОЛ")
        XCTAssertEqual(OnboardingStartCopy.title(locale: locale), "Инициализация рабочего профиля")
        XCTAssertEqual(OnboardingStartCopy.primaryAction(locale: locale), "Запустить быструю настройку")
        XCTAssertEqual(OnboardingStartCopy.checkpoints(locale: locale).count, 3)
    }

    func testEnglishCopyUsesIndustrialTone() {
        let locale = Locale(identifier: "en_US")

        XCTAssertEqual(OnboardingStartCopy.badge(locale: locale), "STARTUP PROTOCOL")
        XCTAssertEqual(OnboardingStartCopy.title(locale: locale), "Initialize your working profile")
        XCTAssertEqual(OnboardingStartCopy.secondaryAction(locale: locale), "Skip and enter workspace")
        XCTAssertEqual(OnboardingStartCopy.checkpoints(locale: locale).count, 3)
    }
}
