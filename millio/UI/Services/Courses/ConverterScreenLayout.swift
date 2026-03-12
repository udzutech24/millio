import Foundation
import CoreGraphics

/// Центральный расчет вертикального layout для экрана конвертера.
/// Держим его вне View, чтобы безопасно тестировать визуальные правки.
struct ConverterScreenLayout: Equatable {
    let totalHeight: CGFloat
    let bottomSafeArea: CGFloat
    let contentGap: CGFloat
    let keySpacing: CGFloat
    let desiredRows: Int
    let rowSpacing: CGFloat
    let rowHeight: CGFloat
    let keyHeight: CGFloat
    let fontSize: CGFloat
    let listBlockHeight: CGFloat
    let keypadBlockHeight: CGFloat
    let bottomPadding: CGFloat
}

enum ConverterScreenLayoutCalculator {
    static func makeLayout(totalHeight: CGFloat, bottomSafeArea: CGFloat) -> ConverterScreenLayout {
        let isTallScreen = totalHeight >= 900
        // Пользовательский визуальный приоритет: клавиатура должна сидеть чуть ниже
        // относительно последней валютной строки, а не прилипать к ней.
        let contentGap: CGFloat = isTallScreen ? 28 : 24

        let availableHeight = max(
            0,
            totalHeight - bottomSafeArea - contentGap - 8
        )

        let listRatio: CGFloat = isTallScreen ? 0.56 : 0.60
        let rawListHeight = floor(availableHeight * listRatio)
        let rawKeypadHeight = max(0, availableHeight - rawListHeight)
        let listBlockHeight = max(280, rawListHeight)
        let keypadBlockHeight = max(200, rawKeypadHeight)

        let desiredRows = 6
        let rowSpacing: CGFloat = availableHeight < 700 ? 8 : 10
        let keySpacing: CGFloat = availableHeight < 700 ? 8 : 10

        let rawRowHeight = (listBlockHeight - CGFloat(desiredRows - 1) * rowSpacing) / CGFloat(desiredRows)
        let rowHeight = min(74, max(56, floor(rawRowHeight)))

        let rawKeyHeight = (keypadBlockHeight - CGFloat(5 - 1) * keySpacing) / 5
        let keyHeightMax: CGFloat = isTallScreen ? 80 : 74
        let keyHeight = min(keyHeightMax, max(52, floor(rawKeyHeight)))
        let fontSize: CGFloat = keyHeight >= 68 ? 24 : (keyHeight >= 60 ? 22 : 20)

        let safeRowHeight = rowHeight.isFinite && rowHeight > 0 ? rowHeight : 62
        let safeRowSpacing = rowSpacing.isFinite && rowSpacing >= 0 ? rowSpacing : 8
        let safeKeyHeight = keyHeight.isFinite && keyHeight > 0 ? keyHeight : 60
        let safeKeySpacing = keySpacing.isFinite && keySpacing >= 0 ? keySpacing : 8
        let safeFontSize = fontSize.isFinite && fontSize > 0 ? fontSize : 18

        return ConverterScreenLayout(
            totalHeight: totalHeight,
            bottomSafeArea: bottomSafeArea,
            contentGap: contentGap,
            keySpacing: safeKeySpacing,
            desiredRows: desiredRows,
            rowSpacing: safeRowSpacing,
            rowHeight: safeRowHeight,
            keyHeight: safeKeyHeight,
            fontSize: safeFontSize,
            listBlockHeight: listBlockHeight,
            keypadBlockHeight: keypadBlockHeight,
            bottomPadding: max(0, bottomSafeArea - 12)
        )
    }
}
