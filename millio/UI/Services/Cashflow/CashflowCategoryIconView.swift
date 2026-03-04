//
//  CashflowCategoryIconView.swift
//  millio
//
//  Created by Codex on 04.03.2026.
//

import SwiftUI

struct CashflowCategoryIconView: View {
    let icon: String
    let fontSize: CGFloat
    let fontWeight: Font.Weight
    let tint: AnyShapeStyle

    var body: some View {
        if CashflowCustomCategory.isSFSymbolIcon(icon) {
            Image(systemName: icon)
                .font(.system(size: fontSize, weight: fontWeight))
                .foregroundStyle(tint)
        } else {
            Text(icon)
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(tint)
        }
    }
}
