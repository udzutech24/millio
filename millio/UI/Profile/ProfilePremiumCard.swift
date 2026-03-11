//
//  ProfilePremiumCard.swift
//  millio
//
//  Created by Assistant on 11.03.2026.
//

import SwiftUI

struct ProfilePremiumCard: View {
    let titleKey: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                iconTile

                VStack(alignment: .leading, spacing: 6) {
                    Text(titleKey)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text("profile.premium.details")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.96))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(cardBackground)
            .overlay(cardStroke)
            .shadow(color: AppColors.premiumShadow.opacity(0.55), radius: 18, x: 0, y: 10)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "161D54"),
                            Color(hex: "1A0F3A")
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)

            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            AppColors.premiumOrbBlue,
                            Color.white.opacity(0.85),
                            Color(hex: "FF9E57"),
                            AppColors.premiumOrbViolet
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .padding(12)
                .blur(radius: 0.2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 2,
                        endRadius: 22
                    )
                )
                .padding(18)

            Image("crown")
                .resizable()
                .scaledToFit()
                .padding(14)
                .shadow(color: Color.white.opacity(0.18), radius: 8, x: 0, y: 2)
        }
        .frame(width: 74, height: 74)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AppColors.premiumSurfaceStart,
                        Color(hex: "18235D"),
                        AppColors.premiumSurfaceEnd
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(AppColors.premiumOrbBlue.opacity(0.30))
                    .frame(width: 116, height: 116)
                    .blur(radius: 30)
                    .offset(x: -34, y: -38)
            }
            .overlay(alignment: .bottomTrailing) {
                Circle()
                    .fill(AppColors.premiumOrbViolet.opacity(0.28))
                    .frame(width: 112, height: 112)
                    .blur(radius: 30)
                    .offset(x: 34, y: 34)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColors.premiumHighlight,
                                Color.clear,
                                Color.black.opacity(0.12)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
    }

    private var cardStroke: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.30),
                        AppColors.premiumBorder,
                        Color.white.opacity(0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}
