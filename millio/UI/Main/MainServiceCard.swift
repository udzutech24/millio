//
//  MainServiceCard.swift
//  millio
//
//  Created by Codex on 03.04.2026.
//

import SwiftUI

struct MainServiceCard: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void

    private var accent: Color {
        gradientColors.first ?? AppColors.brandPrimary
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(accent.opacity(0.14), lineWidth: 0.8)
                            )

                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                    }
                    .frame(width: 54, height: 54)

                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(Color.white.opacity(0.05))
                        )
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Text(
                        String(
                            localized: "main.service.open",
                            defaultValue: "Open",
                            comment: "Secondary label for opening a service card on the main screen"
                        )
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .mainSectionSurface(tint: accent, cornerRadius: 26)
        }
        .buttonStyle(.plain)
    }
}
