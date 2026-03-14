//
//  ServiceButton.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ServiceButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "161C29").opacity(0.5),
                                Color(hex: "161C29").opacity(0.5)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "0081E7").opacity(0.5),
                                        Color(hex: "19E694").opacity(0.5),
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.06),
                                        Color.white.opacity(0.0)
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    }

                HStack(spacing: 12) {
                    ZStack {
                        Image(icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 48, height: 48)
                    }
                    .frame(width: 76, height: 68, alignment: .center)

                    Text(title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .offset(y: -0.5)
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 68)
        }
        .buttonStyle(.plain)
    }
}
