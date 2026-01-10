//
//  CardIndexView.swift
//  millio
//
//  Created by Александр Сидоркин on 10.01.2026.
//

import SwiftUI

struct CardIndexView: View {
    var body: some View {
        ZStack {
            GradientBackground()
            
            VStack {
                Text("Картотека")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .navigationTitle("Картотека")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        CardIndexView()
    }
}
