import Testing
@testable import millio
internal import CoreFoundation

struct ToolbarGlassIconButtonStyleTests {
    @Test("Размер плоской toolbar-кнопки остается стабильным")
    func buttonSizeIsStable() {
        #expect(ToolbarGlassIconButtonStyle.visualSize == 36)
    }

    @Test("Disabled-состояние ослабляет иконку")
    func disabledStateLowersIconOpacity() {
        #expect(
            ToolbarGlassIconButtonStyle.iconOpacity(isEnabled: false)
                < ToolbarGlassIconButtonStyle.iconOpacity(isEnabled: true)
        )
    }
}
