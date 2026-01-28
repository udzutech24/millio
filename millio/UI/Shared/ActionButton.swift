//
//  ActionButton.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct ActionButton: View {
    let title: String
    let icon: String
    let gradientColors: [Color]
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                
                // MARK: Glass Icon Circle
                ZStack {
                    Circle()
                        .fill(Color.clear)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: gradientColors,
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        )
                        .frame(width: 48, height: 48)
                        
                    
                    Image(icon)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(.white)
                }
                .padding(.leading, 10)
                
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                
                Spacer()
            }
            .frame(height: 68) 
            .background {
                ZStack {

                    
                    // Gradient stroke
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            lineWidth: 1
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}


