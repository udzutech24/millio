//
//  FinanceChartStyle.swift
//  millio
//
//  Централизует визуальные параметры финансового графика,
//  чтобы его стиль был консистентным и покрывался unit-тестами.
//

import CoreGraphics
import Foundation

enum FinanceChartCurve: String {
    case monotone
    case catmullRom
}

enum FinanceChartStyle {
    static let curve: FinanceChartCurve = .catmullRom
    static let lineWidth: CGFloat = 2.4
    static let lineShadowRadius: CGFloat = 14
    static let lineShadowYOffset: CGFloat = 3
    static let areaTopOpacity: Double = 0.20
    static let areaMiddleOpacity: Double = 0.07
    static let areaBottomOpacity: Double = 0.015
    static let selectionOuterDiameter: CGFloat = 12
    static let selectionInnerDiameter: CGFloat = 4
    static let selectionRingLineWidth: CGFloat = 2
    static let selectionShadowRadius: CGFloat = 12
}
