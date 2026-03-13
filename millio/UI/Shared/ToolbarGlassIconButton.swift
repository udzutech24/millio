//
//  ToolbarGlassIconButton.swift
//  millio
//

import SwiftUI

enum ToolbarGlassIconButtonStyle {
    static let visualSize: CGFloat = 36
    static let iconSize: CGFloat = 18

    static func iconOpacity(isEnabled: Bool) -> Double {
        isEnabled ? 0.9 : 0.32
    }
}

struct ToolbarGlassIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var isEnabled: Bool = true
    var isHighlighted: Bool = false
    let action: () -> Void

    private let highlightColor = Color(red: 0.22, green: 1.0, blue: 0.56)
    private let flatFillColor = Color.white.opacity(0.08)

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(
                    isEnabled && isHighlighted
                    ? highlightColor.opacity(0.28)
                    : flatFillColor
                )
                .overlay {
                    Image(systemName: systemName)
                        .font(.system(size: ToolbarGlassIconButtonStyle.iconSize, weight: .regular))
                        .foregroundStyle(AppColors.textPrimary.opacity(ToolbarGlassIconButtonStyle.iconOpacity(isEnabled: isEnabled)))
                }
                .frame(
                    width: ToolbarGlassIconButtonStyle.visualSize,
                    height: ToolbarGlassIconButtonStyle.visualSize
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(accessibilityLabel)
    }
}
