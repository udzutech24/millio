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

    @Test("ScrollView не получает лишний отступ сверху, если clearance не нужен")
    func scrollContentTopPaddingUsesBaseWhenNotNeeded() {
        #expect(
            FinanceDynamicsTopBarStyle.scrollContentTopPadding(needsClearance: false) ==
                FinanceDynamicsTopBarStyle.baseScrollContentTopPadding
        )
    }

    @Test("ScrollView получает дополнительный отступ сверху, если нужно уйти из-под navigation bar в деталях кредитной карты")
    func scrollContentTopPaddingAddsConfiguredClearance() {
        #expect(
            FinanceDynamicsTopBarStyle.scrollContentTopPadding(needsClearance: true) ==
                FinanceDynamicsTopBarStyle.baseScrollContentTopPadding +
                FinanceDynamicsTopBarStyle.singleAccountCreditCardScrollContentClearanceTopPadding
        )
    }

    @Test("Селектор периода опускается ниже, чтобы не пересекаться с графиком")
    func periodSelectorTopPaddingIsStable() {
        #expect(FinanceDynamicsTopBarStyle.periodSelectorTopPadding >= 6)
    }
}
