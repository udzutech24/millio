import Testing
@testable import millio
internal import CoreFoundation

struct ServiceButtonStyleTests {
    @Test("Карточка сервиса использует увеличенную высоту для более спокойного ритма")
    func buttonHeightIsStable() {
        #expect(ServiceButtonStyle.height == 74)
    }

    @Test("Иконка сервиса визуально усилена и привязана к левому краю")
    func iconMetricsFavorLeftAnchoredLayout() {
        #expect(ServiceButtonStyle.iconSize > 48)
        #expect(ServiceButtonStyle.iconContainerSize < 64)
        #expect(ServiceButtonStyle.horizontalPadding <= 16)
    }

    @Test("Заголовок сервиса остался читаемым в стиле iOS")
    func titleSizeMatchesPrimaryActionHierarchy() {
        #expect(ServiceButtonStyle.titleSize == 17)
    }
}
