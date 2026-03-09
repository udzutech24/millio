import Testing
import CoreGraphics
@testable import millio

struct FinanceDynamicsTopBarStyleTests {
    @Test("Левая кнопка показывает явный редактор в обычном режиме")
    func editorButtonUsesEditorSymbolWhenNotEditing() {
        #expect(FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: false) == "square.and.pencil")
    }

    @Test("Левая кнопка переключается на сохранение во время inline-редактирования")
    func editorButtonUsesSaveSymbolWhenEditing() {
        #expect(FinanceDynamicsTopBarStyle.inlineEditorSymbol(isEditing: true) == "checkmark")
    }

    @Test("Название счета не смещается, если clearance не нужен")
    func singleAccountTitleTopPaddingIsZeroWhenNotNeeded() {
        #expect(FinanceDynamicsTopBarStyle.singleAccountTitleTopPadding(needsClearance: false) == CGFloat.zero)
    }

    @Test("Название счета получает вертикальный отступ, если нужно уйти из-под bar-кнопок")
    func singleAccountTitleTopPaddingUsesConfiguredClearance() {
        #expect(
            FinanceDynamicsTopBarStyle.singleAccountTitleTopPadding(needsClearance: true) ==
                FinanceDynamicsTopBarStyle.singleAccountTitleClearanceTopPadding
        )
    }
}
