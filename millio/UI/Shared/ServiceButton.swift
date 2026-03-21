//
//  ServiceButton.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

enum ServiceButtonStyle {
    static let height: CGFloat = 74
    static let cornerRadius: CGFloat = 24
    static let horizontalPadding: CGFloat = 16
    static let contentSpacing: CGFloat = 14
    static let iconContainerSize: CGFloat = 62
    static let iconSize: CGFloat = 60
    static let titleSize: CGFloat = 17

    static let baseFillTop = Color(hex: "11161F").opacity(0.82)
    static let baseFillBottom = Color(hex: "090C12").opacity(0.72)
    static let borderHighlight = Color.white.opacity(0.08)
    static let shadowColor = Color.black.opacity(0.26)
}

struct ServiceButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: ServiceButtonStyle.contentSpacing) {
                ZStack {
                    Image(icon)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: ServiceButtonStyle.iconSize,
                            height: ServiceButtonStyle.iconSize
                        )
                }
                .frame(
                    width: ServiceButtonStyle.iconContainerSize,
                    height: ServiceButtonStyle.iconContainerSize
                )

                Text(title)
                    .font(.system(size: ServiceButtonStyle.titleSize, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary.opacity(0.96))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, ServiceButtonStyle.horizontalPadding)
            .frame(height: ServiceButtonStyle.height)
            .background {
                RoundedRectangle(
                    cornerRadius: ServiceButtonStyle.cornerRadius,
                    style: .continuous
                )
                .fill(
                    LinearGradient(
                        colors: [
                            ServiceButtonStyle.baseFillTop,
                            ServiceButtonStyle.baseFillBottom
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: ServiceButtonStyle.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        LinearGradient(
                            colors: gradientColors.map { $0.opacity(0.38) },
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 0.72
                    )
                }
                .overlay(alignment: .top) {
                    RoundedRectangle(
                        cornerRadius: ServiceButtonStyle.cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(ServiceButtonStyle.borderHighlight, lineWidth: 0.6)
                    .blur(radius: 0.4)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .shadow(
                    color: ServiceButtonStyle.shadowColor,
                    radius: 12,
                    x: 0,
                    y: 6
                )
            }
        }
        .buttonStyle(.plain)
    }
}
