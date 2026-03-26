import CoreGraphics
import SwiftUI
import UIKit
import Testing
@testable import millio

struct CalendarRangeThemeTests {
    @Test("Cashflow calendar theme uses the blue date outlines from the design")
    func cashflowThemeUsesBlueDateOutlines() {
        #expect(CalendarRangeTheme.cashflow.ringColor.toHex() == "#3c6fc4")
        #expect(CalendarRangeTheme.cashflow.secondaryRingColor.toHex() == "#2e5a9d")
        #expect(CalendarRangeTheme.cashflow.inactiveDayStroke.toHex() == "#ffffff")
        #expect(CalendarRangeTheme.cashflow.inactiveDayStroke.alphaComponent().isApproximatelyEqual(to: 0.12))
    }

    @Test("Finances calendar theme matches the subdued blue selected range treatment")
    func financesThemeUsesMutedBlueSelectionAndNeutralInactiveStroke() {
        #expect(CalendarRangeTheme.finances.ringColor.toHex() == "#3c6fc4")
        #expect(CalendarRangeTheme.finances.secondaryRingColor.toHex() == "#2e5a9d")
        #expect(CalendarRangeTheme.finances.inactiveDayStroke.toHex() == "#ffffff")
        #expect(CalendarRangeTheme.finances.inactiveDayStroke.alphaComponent().isApproximatelyEqual(to: 0.12))
    }

    @Test("Cashback calendar theme keeps the blue outline from the design")
    func cashbackThemeUsesBlueAccent() {
        #expect(CalendarRangeTheme.cashback.ringColor.toHex() == "#1d76ff")
        #expect(CalendarRangeTheme.cashback.secondaryRingColor.toHex() == "#1455c5")
    }

    @Test("Cashback calendar theme dims future days more aggressively")
    func cashbackThemeUsesLowerDisabledOpacity() {
        #expect(CalendarRangeTheme.cashback.disabledDayOpacity == 0.18)
        #expect(CalendarRangeTheme.cashback.disabledDayOpacity < CalendarRangeTheme.cashflow.disabledDayOpacity)
    }

    @Test("Range picker panel can suppress single-day highlight for range-only selection")
    func rangePickerPanelSupportsRangeOnlySelectionMode() {
        let panel = CalendarRangePickerPanel(
            title: nil,
            subtitle: nil,
            startDate: .constant(Date()),
            endDate: .constant(Date()),
            theme: .cashflow,
            highlightsSingleDaySelection: false
        )

        #expect(type(of: panel) == CalendarRangePickerPanel.self)
    }

    @Test("Finances custom period picker also uses range-only selection mode")
    func financesRangePickerCanUseRangeOnlySelectionMode() {
        let panel = CalendarRangePickerPanel(
            title: nil,
            subtitle: nil,
            startDate: .constant(Date()),
            endDate: .constant(Date()),
            theme: .finances,
            highlightsSingleDaySelection: false
        )

        #expect(type(of: panel) == CalendarRangePickerPanel.self)
    }
}

private extension Color {
    func toHex() -> String {
        let uiColor = UIColor(self)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        let rgb = Int(red * 255) << 16 | Int(green * 255) << 8 | Int(blue * 255)
        return String(format: "#%06x", rgb)
    }

    func alphaComponent() -> CGFloat {
        UIColor(self).cgColor.alpha
    }
}

private extension CGFloat {
    func isApproximatelyEqual(to value: CGFloat, tolerance: CGFloat = 0.001) -> Bool {
        abs(self - value) <= tolerance
    }
}
