//
//  MainLayoutModePicker.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import SwiftUI

struct MainLayoutModePicker: View {
    let selectedMode: MainScreenLayoutMode
    let onSelect: (MainScreenLayoutMode) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MainScreenLayoutMode.allCases, id: \.self) { mode in
                Button {
                    onSelect(mode)
                } label: {
                    Text(MainLocalization.text(titleKey(for: mode)))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selectedMode == mode ? AppColors.textPrimary : AppColors.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(selectedMode == mode ? Color.white.opacity(0.14) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                )
        )
        .accessibilityLabel(MainLocalization.text(MainLocalization.layoutSwitchAccessibility))
    }

    private func titleKey(for mode: MainScreenLayoutMode) -> String {
        switch mode {
        case .classic:
            return MainLocalization.layoutClassic
        case .focus:
            return MainLocalization.layoutFocus
        }
    }
}
