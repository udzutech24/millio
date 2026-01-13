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
            ZStack(alignment: .topLeading) {
                
                // Фон
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
                
                // Текст
                Text(title)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.leading, 16)
                    .padding(.top, 12)
                
                // Иконка снизу справа
                VStack {
                    Spacer()
                    
                    HStack {
                        Spacer()
                        
                        Image(icon)
                            .offset(x: 6, y: 6) // <-- выход за бордер
                    }
                }
            }
            .frame(height: 68)
        }
        .buttonStyle(.plain)
    }
}

